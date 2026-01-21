class L1RpcPrefetcher
  class BlockFetchError < StandardError; end

  def initialize(ethereum_client:,
                 ahead: ENV.fetch('L1_PREFETCH_FORWARD', 100).to_i,
                 threads: ENV.fetch('L1_PREFETCH_THREADS', 10).to_i)
    @eth = ethereum_client
    @ahead = ahead
    @threads = threads
    @fetch_timeout = ENV.fetch('L1_PREFETCH_TIMEOUT', 30).to_i

    @pool = Concurrent::FixedThreadPool.new(threads)
    @promises = Concurrent::Map.new
    @last_chain_tip = @eth.get_block_number
    @highest_queued = 0  # Track highest block we've queued

    Rails.logger.info "L1RpcPrefetcher initialized: #{threads} threads, #{ahead} blocks ahead, #{@fetch_timeout}s timeout"
  end

  # Proactively queue blocks for prefetching - optimized to avoid redundant work
  def ensure_prefetched(from_block)
    # Skip if we've already queued far enough ahead
    return if @highest_queued >= from_block + @ahead

    latest = cached_chain_tip(from_block)
    to_block = [from_block + @ahead, latest].min

    # Only queue blocks we haven't queued yet
    start_block = [@highest_queued + 1, from_block].max
    return if start_block > to_block

    (start_block..to_block).each { |n| enqueue_single(n) }
    @highest_queued = to_block
  end

  # Get block data, waiting if necessary
  def fetch(block_number)
    # Only ensure_prefetched every 10 blocks to reduce overhead
    ensure_prefetched(block_number) if block_number % 10 == 0 || !@promises.key?(block_number)

    promise = @promises[block_number] || enqueue_single(block_number)

    begin
      result = promise.value!(@fetch_timeout)
    rescue => e
      @promises.delete(block_number)
      raise BlockFetchError.new("Block #{block_number} fetch failed: #{e.class} - #{e.message}")
    end

    if result.nil?
      @promises.delete(block_number)
      raise BlockFetchError.new("Block #{block_number} fetch timed out after #{@fetch_timeout}s")
    end

    if result == :not_ready
      @promises.delete(block_number)
      raise BlockFetchError.new("Block #{block_number} not yet available on L1")
    end

    result
  end

  # Memory management - remove old promises
  def clear_older_than(min_keep)
    return if min_keep.nil?

    deleted = 0
    @promises.keys.each do |n|
      if n < min_keep
        @promises.delete(n)
        deleted += 1
      end
    end

    Rails.logger.debug "[PREFETCH] Cleared #{deleted} promises older than #{min_keep}" if deleted > 0
  end

  # Statistics for monitoring
  def stats
    fulfilled = 0
    pending = 0

    @promises.each_pair do |_, promise|
      if promise.fulfilled?
        fulfilled += 1
      elsif promise.pending?
        pending += 1
      end
    end

    {
      promises_total: @promises.size,
      fulfilled: fulfilled,
      pending: pending,
      threads_active: @pool.length,
      threads_queued: @pool.queue_length
    }
  end

  # Graceful shutdown
  def shutdown
    Rails.logger.info "[PREFETCH] Shutting down..."
    @pool.shutdown
    terminated = @pool.wait_for_termination(3)
    @pool.kill unless terminated

    @promises.clear

    if terminated
      Rails.logger.info "[PREFETCH] Thread pool shut down successfully"
    else
      Rails.logger.warn "[PREFETCH] Shutdown timed out after 3s, pool killed"
    end

    terminated
  rescue => e
    Rails.logger.error "[PREFETCH] Error during shutdown: #{e.message}"
    false
  end

  private

  def enqueue_single(block_number)
    @promises.compute_if_absent(block_number) do
      Concurrent::Promise.execute(executor: @pool) do
        fetch_job(block_number)
      end.rescue do |e|
        Rails.logger.error "[PREFETCH] Block #{block_number}: #{e.class} - #{e.message}"
        @promises.delete(block_number)
        raise e
      end
    end
  end

  def fetch_job(block_number)
    block_response = @eth.get_block(block_number)

    # Handle case where block doesn't exist yet
    if block_response.nil? || block_response.dig('result', 'hash').nil?
      return :not_ready
    end

    receipts_response = @eth.get_transaction_receipts(block_number)
    receipts = receipts_response.dig('result', 'receipts')
    result = block_response['result']
    tx_count = result['transactions'].size

    unless receipts
      Rails.logger.warn "[PREFETCH] Block #{block_number}: receipts missing"
      return :not_ready
    end

    # Validate receipts count matches transactions - incomplete receipts can cause lost ethscriptions
    if receipts.size != tx_count
      Rails.logger.warn "[PREFETCH] Block #{block_number}: receipts count mismatch (#{receipts.size} vs #{tx_count} txs)"
      return :not_ready
    end

    block_timestamp = result['timestamp'].to_i(16)
    block_blockhash = result['hash']

    relevant_transactions = build_relevant_transactions(
      block_number: block_number,
      block_timestamp: block_timestamp,
      block_blockhash: block_blockhash,
      transactions: result['transactions'],
      receipts: receipts
    )

    {
      block_number: block_number,
      block_response: block_response,
      receipts_response: receipts_response,
      relevant_transactions: relevant_transactions
    }
  end

  def build_relevant_transactions(block_number:, block_timestamp:, block_blockhash:, transactions:, receipts:)
    receipts_by_hash = receipts.index_by { |r| r['transactionHash'] }

    tx_instances = transactions.map do |tx|
      receipt = receipts_by_hash[tx['hash']]
      next unless receipt

      gas_price = receipt['effectiveGasPrice'].to_i(16).to_d
      gas_used = receipt['gasUsed'].to_i(16).to_d

      # Pre-Byzantium blocks (before 4370000) didn't have status field
      status_value = block_number <= 4370000 ? nil : receipt['status']&.to_i(16)

      EthTransaction.new(
        block_number: block_number,
        block_timestamp: block_timestamp,
        block_blockhash: block_blockhash,
        transaction_hash: tx['hash'],
        from_address: tx['from'],
        to_address: tx['to'],
        created_contract_address: receipt['contractAddress'],
        transaction_index: tx['transactionIndex'].to_i(16),
        input: tx['input'],
        status: status_value,
        logs: receipt['logs'],
        gas_price: gas_price,
        gas_used: gas_used,
        transaction_fee: gas_price * gas_used,
        value: tx['value'].to_i(16).to_d,
        blob_versioned_hashes: tx['blobVersionedHashes'].presence || []
      )
    end.compact

    tx_instances.select(&:possibly_relevant?)
  end

  def cached_chain_tip(from_block)
    distance = @last_chain_tip - from_block

    if distance > 10
      # Far from tip, use cached value
      @last_chain_tip
    else
      # Near tip, refresh
      @last_chain_tip = @eth.get_block_number
    end
  end
end
