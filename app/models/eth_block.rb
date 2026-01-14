class EthBlock < ApplicationRecord
  include FacetRailsCommon::OrderQuery
  class BlockNotReadyToImportError < StandardError; end

  initialize_order_query({
    newest_first: [[:block_number, :desc, unique: true]],
    oldest_first: [[:block_number, :asc, unique: true]]
  }, page_key_attributes: [:block_number])
    
  %i[
    eth_transactions
    ethscriptions
    ethscription_transfers
    ethscription_ownership_versions
    token_states
  ].each do |association|
    has_many association,
      foreign_key: :block_number,
      primary_key: :block_number,
      inverse_of: :eth_block
  end
  
  def self.rpc_client
    @_rpc_client ||= PooledRpcClient.new(
      base_url: ENV.fetch('ETHEREUM_CLIENT_BASE_URL'),
      api_key: ENV['ETHEREUM_CLIENT_API_KEY']
    )
  end

  def self.prefetcher
    @_prefetcher ||= L1RpcPrefetcher.new(ethereum_client: rpc_client)
  end

  def self.reset_prefetcher!
    @_prefetcher&.shutdown
    @_prefetcher = nil
  end
  
  def self.beacon_client
    @_beacon_client ||= begin
      EthereumBeaconNodeClient.new(
        api_key: ENV['ETHEREUM_BEACON_NODE_API_KEY'],
        base_url: ENV.fetch('ETHEREUM_BEACON_NODE_API_BASE_URL')
      )
    end
  end
    
  def self.genesis_blocks
    blocks = if ENV.fetch('ETHEREUM_NETWORK') == "eth-mainnet"
      [1608625, 3369985, 3981254, 5873780, 8205613, 9046950,
      9046974, 9239285, 9430552, 10548855, 10711341, 15437996, 17478950]
    else
      [[ENV.fetch('TESTNET_START_BLOCK').to_i, 4370001].max]
    end
  
    @_genesis_blocks ||= blocks.sort.freeze
  end
  
  def self.most_recently_imported_block_number
    EthBlock.where.not(imported_at: nil).order(block_number: :desc).limit(1).pluck(:block_number).first
  end
  
  def self.most_recently_imported_blockhash
    EthBlock.where.not(imported_at: nil).order(block_number: :desc).limit(1).pluck(:blockhash).first
  end
  
  def self.blocks_behind
    (cached_global_block_number - next_block_to_import) + 1
  end
  
  def self.import_blocks_until_done
    blocks_imported = 0
    start_time = Time.current
    total_ethscriptions = 0

    loop do
      begin
        block_number = next_block_to_import
        raise BlockNotReadyToImportError.new("No block to import") if block_number.nil?

        response = prefetcher.fetch(block_number)
        result = import_block(
          block_number,
          response[:block_response],
          response[:relevant_transactions]
        )

        total_ethscriptions += result.ethscriptions_imported
        blocks_imported += 1
        prefetcher.clear_older_than(block_number - 10)

        if blocks_imported % 100 == 0
          elapsed = Time.current - start_time
          rate = (blocks_imported / elapsed).round(1)
          stats = prefetcher.stats
          puts "Imported #{blocks_imported} blocks (#{rate} bl/s) | #{total_ethscriptions} ethscriptions | Prefetcher: #{stats[:fulfilled]}/#{stats[:fulfilled] + stats[:pending]} ready"
        end

      rescue BlockNotReadyToImportError, L1RpcPrefetcher::BlockFetchError => e
        puts "#{e.message}. Stopping import."
        break
      end
    end
  end

  def self.import_block(block_number, block_by_number_response, relevant_transactions)
    ActiveRecord::Base.transaction do
      result = block_by_number_response['result']

      parent_block = EthBlock.find_by(block_number: block_number - 1)

      if (block_number > genesis_blocks.max) && parent_block.blockhash != result['parentHash']
        Airbrake.notify("
          Reorg detected: #{block_number},
          #{parent_block.blockhash},
          #{result['parentHash']},
          Deleting block(s): #{EthBlock.where("block_number >= ?", parent_block.block_number).pluck(:block_number).join(', ')}
        ")

        EthBlock.where("block_number >= ?", parent_block.block_number).delete_all

        # Clear prefetcher cache - it has stale data from the old chain
        reset_prefetcher!

        return OpenStruct.new(ethscriptions_imported: 0)
      end

      block_record = create!(
        block_number: block_number,
        blockhash: result['hash'],
        parent_blockhash: result['parentHash'],
        parent_beacon_block_root: result['parentBeaconBlockRoot'],
        timestamp: result['timestamp'].to_i(16),
        is_genesis_block: genesis_blocks.include?(block_number)
      )

      ethscriptions_imported = 0

      if relevant_transactions.present?
        EthTransaction.import!(relevant_transactions)

        eth_transactions = EthTransaction.where(block_number: block_number).order(transaction_index: :asc)
        eth_transactions.each(&:process!)

        ethscriptions_imported = eth_transactions.map(&:ethscription).compact.size
      end

      EthTransaction.prune_transactions(block_number)
      Token.process_block(block_record)
      block_record.create_attachments_for_previous_block
      block_record.update!(imported_at: Time.current)

      puts "Block Importer: imported block #{block_number}"

      OpenStruct.new(ethscriptions_imported: ethscriptions_imported)
    end
  rescue ActiveRecord::RecordNotUnique => e
    if e.message.include?("eth_blocks") && e.message.include?("block_number")
      logger.info "Block Importer: Block #{block_number} already exists"
      raise ActiveRecord::Rollback
    else
      raise
    end
  end
  
  def ensure_blob_sidecars(beacon_block_root = nil)
    if blob_sidecars.present? && blob_sidecars.first['blob'].present?
      return blob_sidecars
    end
    
    beacon_block_root ||= EthBlock.where(block_number: block_number + 1).pick(:parent_beacon_block_root)
    
    raise "Need beacon root" unless beacon_block_root.present?
    
    self.blob_sidecars = EthBlock.beacon_client.get_blob_sidecars(beacon_block_root)
  end
  
  def create_attachments_for_previous_block
    return unless EthTransaction.esip8_enabled?(block_number - 1)
    
    scope = EthTransaction.with_blobs.joins(:ethscription).where(block_number: block_number - 1)
    
    return unless scope.exists?
    
    prev_block = EthBlock.find_by(block_number: block_number - 1)
    
    prev_block.ensure_blob_sidecars(parent_beacon_block_root)
    
    scope.find_each do |tx|
      tx.block_blob_sidecars = prev_block.blob_sidecars
      tx.create_ethscription_attachment_if_needed!
    end
    
    prev_block.blob_sidecars = prev_block.blob_sidecars.map do |sidecar|
      sidecar.except('blob')
    end
    
    # TODO: Update state attestation hash
    prev_block.save!
  end
  
  def self.uncached_global_block_number
    rpc_client.get_block_number.tap do |block_number|
      Rails.cache.write('global_block_number', block_number, expires_in: 1.second)
    end
  end
  
  def self.cached_global_block_number
    Rails.cache.read('global_block_number') || uncached_global_block_number
  end
  
  def self.next_block_to_import
    next_blocks_to_import(1).first
  end
  
  def self.next_blocks_to_import(n)
    max_db_block = EthBlock.maximum(:block_number)
    
    return genesis_blocks.sort.first(n) unless max_db_block
    
    if max_db_block < genesis_blocks.max
      imported_genesis_blocks = EthBlock.where.not(imported_at: nil).where(block_number: genesis_blocks).pluck(:block_number).to_set
      remaining_genesis_blocks = (genesis_blocks.to_set - imported_genesis_blocks).sort
      return remaining_genesis_blocks.first(n)
    end
  
    (max_db_block + 1..max_db_block + n).to_a
  end
  
end
