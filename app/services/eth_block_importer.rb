class EthBlockImporter
  include SysConfig
  include Memery
  
  # Raised when the next block to import is not yet available on L1
  class BlockNotReadyToImportError < StandardError; end
  # Raised when a re-org is detected (parent hash mismatch)
  class ReorgDetectedError < StandardError; end
  
  attr_accessor :ethscriptions_block_cache, :ethereum_client, :eth_block_cache, :geth_driver

  def initialize
    @ethscriptions_block_cache = {}
    @eth_block_cache = {}

    @ethereum_client ||= EthRpcClient.l1

    @geth_driver = GethDriver

    # Validation configuration
    @validation_enabled = ENV.fetch('VALIDATE_IMPORT').casecmp?('true')
    @validation_stats = {passed: 0, failed: 0}

    # Create a shared thread pool for validation
    if @validation_enabled
      @validation_threads = ENV.fetch('VALIDATION_THREADS', '10').to_i
      @validation_executor = Concurrent::ThreadPoolExecutor.new(
        min_threads: 1,
        max_threads: @validation_threads,
        max_queue: 100,
        fallback_policy: :caller_runs
      )
      logger.info "Created validation thread pool with #{@validation_threads} threads"
    end

    # L1 prefetcher for blocks/receipts/API data
    @prefetcher = L1RpcPrefetcher.new(
      ethereum_client: @ethereum_client,
      ahead: ENV.fetch('L1_PREFETCH_FORWARD', Rails.env.test? ? 5 : 20).to_i,
      threads: ENV.fetch('L1_PREFETCH_THREADS', Rails.env.test? ? 2 : 2).to_i
    )
    @prefetched_api_data = {}

    logger.info "EthBlockImporter initialized - Validation: #{@validation_enabled ? 'ENABLED' : 'disabled'}"

    MemeryExtensions.clear_all_caches!

    set_eth_block_starting_points
    populate_ethscriptions_block_cache

    unless Rails.env.test?
      max_block = current_max_eth_block_number
      if max_block && max_block > 0
        ImportProfiler.start('prefetch_warmup')
        @prefetcher.ensure_prefetched(max_block + 1)
        ImportProfiler.stop('prefetch_warmup')
      end
    end
  end
  
  def current_max_ethscriptions_block_number
    ethscriptions_block_cache.keys.max
  end
  
  def current_max_eth_block_number
    eth_block_cache.keys.max
  end
  
  def current_max_eth_block
    eth_block_cache[current_max_eth_block_number]
  end
  
  def populate_ethscriptions_block_cache
    epochs_found = 0
    current_block_number = current_max_ethscriptions_block_number - 1
    
    while epochs_found < 64 && current_block_number >= 0
      hex_block_number = "0x#{current_block_number.to_s(16)}"
      ImportProfiler.start("l2_block_fetch")
      block_data = geth_driver.client.call("eth_getBlockByNumber", [hex_block_number, false])
      ImportProfiler.stop("l2_block_fetch")
      current_block = EthscriptionsBlock.from_rpc_result(block_data)

      ImportProfiler.start("l1_attributes_fetch")
      l1_attributes = GethDriver.client.get_l1_attributes(current_block.number)
      ImportProfiler.stop("l1_attributes_fetch")
      current_block.assign_l1_attributes(l1_attributes)
      
      ethscriptions_block_cache[current_block.number] = current_block

      if current_block.sequence_number == 0 || current_block_number == 0
        epochs_found += 1
        logger.info "Found epoch #{epochs_found} at block #{current_block_number}"
      end

      current_block_number -= 1
    end

    logger.info "Populated facet block cache with #{ethscriptions_block_cache.size} blocks from #{epochs_found} epochs"
  end
  
  def logger
    Rails.logger
  end
  
  def blocks_behind
    (current_block_number - next_block_to_import) + 1
  end
  
  def current_block_number
    ethereum_client.get_block_number
  end
  memoize :current_block_number, ttl: 12.seconds
  
  def import_batch_size
    [blocks_behind, ENV.fetch('BLOCK_IMPORT_BATCH_SIZE', 2).to_i].min
  end
  
  def find_first_l2_block_in_epoch(l2_block_number_candidate)
    l1_attributes = GethDriver.client.get_l1_attributes(l2_block_number_candidate)
    
    if l1_attributes[:sequence_number] == 0
      return l2_block_number_candidate
    end
    
    return find_first_l2_block_in_epoch(l2_block_number_candidate - 1)
  end
  
  def set_eth_block_starting_points
    latest_l2_block = GethDriver.client.call("eth_getBlockByNumber", ["latest", false])
    latest_l2_block_number = latest_l2_block['number'].to_i(16)
    
    if latest_l2_block_number == 0
      l1_block = EthRpcClient.l1.get_block(SysConfig.l1_genesis_block_number)
      eth_block = EthBlock.from_rpc_result(l1_block)
      ethscriptions_block = EthscriptionsBlock.from_rpc_result(latest_l2_block)
      l1_attributes = GethDriver.client.get_l1_attributes(latest_l2_block_number)
      
      ethscriptions_block.assign_l1_attributes(l1_attributes)
      
      ethscriptions_block_cache[0] = ethscriptions_block
      eth_block_cache[eth_block.number] = eth_block
      
      return [eth_block.number, 0]
    end
    
    l1_attributes = GethDriver.client.get_l1_attributes(latest_l2_block_number)
    
    l1_candidate = l1_attributes[:number]
    l2_candidate = latest_l2_block_number
    
    max_iterations = 1000
    iterations = 0
    
    while iterations < max_iterations
      l2_candidate = find_first_l2_block_in_epoch(l2_candidate)
      
      l1_result = ethereum_client.get_block(l1_candidate)
      l1_hash = Hash32.from_hex(l1_result['hash'])
      
      l1_attributes = GethDriver.client.get_l1_attributes(l2_candidate)
      
      l2_block = GethDriver.client.call("eth_getBlockByNumber", ["0x#{l2_candidate.to_s(16)}", false])
      
      # Check if hashes match AND we're at least 31 blocks in the past
      retry_offset = 31  # batch_size + 1
      blocks_behind = latest_l2_block_number - l2_candidate

      if l1_hash == l1_attributes[:hash] && l1_attributes[:number] == l1_candidate && blocks_behind >= retry_offset
        eth_block_cache[l1_candidate] = EthBlock.from_rpc_result(l1_result)

        ethscriptions_block = EthscriptionsBlock.from_rpc_result(l2_block)
        ethscriptions_block.assign_l1_attributes(l1_attributes)

        ethscriptions_block_cache[l2_candidate] = ethscriptions_block
        logger.info "Found matching block at #{l1_candidate}, #{blocks_behind} blocks behind (minimum #{retry_offset})"
        return [l1_candidate, l2_candidate]
      else
        if l1_hash == l1_attributes[:hash] && l1_attributes[:number] == l1_candidate
          logger.info "Block #{l2_candidate} matches but only #{blocks_behind} blocks behind (need #{retry_offset}), continuing back"
        else
          logger.info "Mismatch on block #{l2_candidate}: #{l1_hash.to_hex} != #{l1_attributes[:hash].to_hex}, decrementing"
        end

        l2_candidate -= 1
        l1_candidate -= 1
      end
      
      iterations += 1
    end
    
    raise "No starting block found after #{max_iterations} iterations"
  end
  
  def import_blocks_until_done
    MemeryExtensions.clear_all_caches!
    
    loop do
      begin
        block_numbers = next_blocks_to_import(import_batch_size)
        
        if block_numbers.blank?
          raise BlockNotReadyToImportError.new("Block not ready")
        end
        
        import_blocks(block_numbers)
      rescue BlockNotReadyToImportError => e
        puts "#{e.message}. Stopping import."
        ImportProfiler.report if ImportProfiler.enabled?
        break
      end
    end
  end
  
  def fetch_block_from_cache(block_number)
    block_number = [block_number, 0].max
    
    ethscriptions_block_cache.fetch(block_number)
  end
  
  def prune_caches
    eth_block_threshold = current_max_eth_block_number - 65
  
    # Remove old entries from eth_block_cache
    eth_block_cache.delete_if { |number, _| number < eth_block_threshold }
  
    # Find the oldest Ethereum block number we want to keep
    oldest_eth_block_to_keep = eth_block_cache.keys.min
  
    # Remove old entries from ethscriptions_block_cache based on Ethereum block number
    ethscriptions_block_cache.delete_if do |_, ethscriptions_block|
      ethscriptions_block.eth_block_number < oldest_eth_block_to_keep
    end

    # Clean up prefetcher and API data caches
    if oldest_eth_block_to_keep
      @prefetcher.clear_older_than(oldest_eth_block_to_keep)
      @prefetched_api_data.delete_if { |block_num, _| block_num < oldest_eth_block_to_keep }
    end
  end
  
  def current_ethscriptions_block(type)
    case type
    when :head
      fetch_block_from_cache(current_max_ethscriptions_block_number)
    when :safe
      find_block_by_epoch_offset(32)
    when :finalized
      find_block_by_epoch_offset(64)
    else
      raise ArgumentError, "Invalid block type: #{type}"
    end
  end
    
  def find_block_by_epoch_offset(offset)
    current_eth_block_number = current_facet_head_block.eth_block_number
    target_eth_block_number = current_eth_block_number - (offset - 1)

    matching_block = ethscriptions_block_cache.values
      .select { |block| block.eth_block_number <= target_eth_block_number }
      .max_by(&:number)

    matching_block || oldest_known_ethscriptions_block
  end
  
  def oldest_known_ethscriptions_block
    ethscriptions_block_cache.values.min_by(&:number)
  end
  
  def current_facet_head_block
    current_ethscriptions_block(:head)
  end
  
  def current_facet_safe_block
    current_ethscriptions_block(:safe)
  end
  
  def current_facet_finalized_block
    current_ethscriptions_block(:finalized)
  end
  
  def import_blocks(block_numbers)
    ImportProfiler.start("import_blocks_total")

    logger.info "Block Importer: importing blocks #{block_numbers.join(', ')}"
    start = Time.current

    ImportProfiler.start("prefetch_ensure")
    @prefetcher.ensure_prefetched(block_numbers.first)
    ImportProfiler.stop("prefetch_ensure")

    eth_blocks = []
    ethscriptions_blocks = []
    res = []
    
    block_numbers.each do |block_number|
      ImportProfiler.start("prefetch_fetch")
      response = @prefetcher.fetch(block_number)
      ImportProfiler.stop("prefetch_fetch")

      eth_block = response[:eth_block]
      ethscriptions_block = response[:ethscriptions_block]
      ethscription_txs = response[:ethscription_txs]

      ethscription_txs.each { |tx| tx.ethscriptions_block = ethscriptions_block }

      if @validation_enabled && response[:api_data]
        @prefetched_api_data[block_number] = response[:api_data]
      end

      parent_eth_block = eth_block_cache[block_number - 1]

      if parent_eth_block && parent_eth_block.block_hash != eth_block.parent_hash
        logger.info "Reorg detected at block #{block_number}"
        raise ReorgDetectedError
      end

      ImportProfiler.start("propose_ethscriptions_block")
      imported_ethscriptions_blocks = propose_ethscriptions_block(
        ethscriptions_block: ethscriptions_block,
        ethscription_txs: ethscription_txs
      )
      ImportProfiler.stop("propose_ethscriptions_block")

      logger.debug "Block #{block_number}: Found #{ethscription_txs.length} ethscription txs, created #{imported_ethscriptions_blocks.length} L2 blocks"
      
      imported_ethscriptions_blocks.each do |ethscriptions_block|
        ethscriptions_block_cache[ethscriptions_block.number] = ethscriptions_block
      end
      
      eth_block_cache[eth_block.number] = eth_block
      
      prune_caches
      
      ethscriptions_blocks.concat(imported_ethscriptions_blocks)
      eth_blocks << eth_block
      
      res << OpenStruct.new(
        ethscriptions_block: imported_ethscriptions_blocks.last,
        transactions_imported: imported_ethscriptions_blocks.last.ethscription_transactions.length
      )
    end
  
    elapsed_time = Time.current - start
  
    blocks = res.map(&:ethscriptions_block)
    total_gas = blocks.sum(&:gas_used)
    total_transactions = res.sum(&:transactions_imported)
    blocks_per_second = (blocks.length / elapsed_time).round(2)
    transactions_per_second = (total_transactions / elapsed_time).round(2)
    total_gas_millions = (total_gas / 1_000_000.0).round(2)
    average_gas_per_block_millions = (total_gas / blocks.length / 1_000_000.0).round(2)
    gas_per_second_millions = (total_gas / elapsed_time / 1_000_000.0).round(2)
  
    logger.info "Time elapsed: #{elapsed_time.round(2)} s"
    logger.info "Imported #{block_numbers.length} blocks. #{blocks_per_second} blocks / s"
    logger.info "Imported #{total_transactions} transactions (#{transactions_per_second} / s)"
    logger.info "Total gas used: #{total_gas_millions} million (avg: #{average_gas_per_block_millions} million / block)"
    logger.info "Gas per second: #{gas_per_second_millions} million / s"

    if block_numbers.length >= 10
      stats = @prefetcher.stats
      logger.info "Prefetcher stats: promises=#{stats[:promises_total]} " \
                  "(fulfilled=#{stats[:promises_fulfilled]}, pending=#{stats[:promises_pending]}, " \
                  "threads_active=#{stats[:threads_active]}, queued=#{stats[:threads_queued]})"
    end

    # Validate imported blocks if enabled
    if @validation_enabled
      if ethscriptions_blocks.any?
        ImportProfiler.start("validation_wall_clock")
        start_validation = Time.current
        logger.info "Starting parallel validation for #{block_numbers.length} blocks with #{ethscriptions_blocks.length} L2 blocks"
        validate_imported_blocks(block_numbers, ethscriptions_blocks)
        validation_time = Time.current - start_validation
        ImportProfiler.stop("validation_wall_clock")
        logger.info "Validation completed in #{validation_time.round(2)}s (#{(block_numbers.length / validation_time).round(2)} blocks/s)"
      else
        logger.info "Validation enabled but no ethscriptions blocks to validate"
      end
    elsif ENV['VALIDATE_IMPORT'] == 'true'
      logger.warn "Validation requested but not enabled in importer initialization"
    end

    ImportProfiler.stop("import_blocks_total")

    # Generate profiling report after each batch
    if ImportProfiler.enabled?
      ImportProfiler.report
      ImportProfiler.reset
    end

    [ethscriptions_blocks, eth_blocks]
  end
  
  def import_next_block
    block_number = next_block_to_import
    import_blocks([block_number])
  end
  
  def next_block_to_import
    next_blocks_to_import(1).first
  end
  
  def next_blocks_to_import(n)
    max_imported_block = current_max_eth_block_number
    
    start_block = max_imported_block + 1
    
    (start_block...(start_block + n)).to_a
  end
  
  def propose_ethscriptions_block(ethscriptions_block:, ethscription_txs:)
    geth_driver.propose_block(
      transactions: ethscription_txs,
      new_ethscriptions_block: ethscriptions_block,
      head_block: current_facet_head_block,
      safe_block: current_facet_safe_block,
      finalized_block: current_facet_finalized_block
    )
  end
  
  def geth_driver
    @geth_driver
  end

  # Validation methods
  private

  def validate_imported_blocks(l1_block_numbers, l2_blocks)
    return unless @validation_enabled

    # Group L2 blocks by their L1 block number
    l2_blocks_by_l1 = {}

    l2_blocks.each do |l2_block|
      l1_num = l2_block.eth_block_number
      l2_blocks_by_l1[l1_num] ||= []
      l2_blocks_by_l1[l1_num] << l2_block.block_hash.to_hex
    end

    # Create validation promises for each block using the shared executor
    validation_promises = l1_block_numbers.map do |l1_block_num|
      l2_hashes = l2_blocks_by_l1[l1_block_num] || []

      Concurrent::Promise.execute(executor: @validation_executor) do
        if l2_hashes.empty?
          {
            block: l1_block_num,
            status: :failed,
            message: "No L2 blocks found for L1 block #{l1_block_num}",
            errors: ["No L2 blocks found for L1 block #{l1_block_num}"]
          }
        else
          begin
            validator = BlockValidator.new
            api_data = @prefetched_api_data.delete(l1_block_num)
            result = validator.validate_l1_block(l1_block_num, l2_hashes, expected_override: api_data)

            if result.stats[:api_unavailable]
              {
                block: l1_block_num,
                status: :failed,
                result: result,
                errors: result.errors.presence || ["API unavailable for block #{l1_block_num}"],
                message: "API unavailable for block #{l1_block_num}"
              }
            elsif result.stats[:incomplete_actual]
              {
                block: l1_block_num,
                status: :failed,
                result: result,
                errors: result.errors.presence || ["Incomplete L2 receipts for block #{l1_block_num}"],
                message: "Incomplete L2 receipts for block #{l1_block_num}"
              }
            else
              payload = {
                block: l1_block_num,
                status: result.success ? :passed : :failed,
                result: result,
                errors: result.errors
              }
              payload
            end
          rescue => e
            {
              block: l1_block_num,
              status: :error,
              message: e.message,
              backtrace: e.backtrace.first(5),
              errors: [e.message]
            }
          end
        end
      end
    end

    # Wait for all validations to complete and process results
    validation_results = validation_promises.map(&:value!)

    # Process results and update stats
    validation_results.each do |validation|
      case validation[:status]
      when :passed
        validation[:result].log_summary(logger)
        @validation_stats[:passed] += 1
      when :failed
        validation[:result]&.log_summary(logger)
        @validation_stats[:failed] += 1
        binding.irb if ENV['DEBUG'] == '1'
        raise "Validation failed for L1 block #{validation[:block]}: #{Array(validation[:errors]).join('; ')}"
      when :error
        logger.error "Validation error for block #{validation[:block]}: #{validation[:message]}"
        logger.error validation[:backtrace].join("\n") if ENV['DEBUG'] && validation[:backtrace]
        @validation_stats[:failed] += 1
        binding.irb if ENV['DEBUG'] == '1'
        raise "Validation failed for L1 block #{validation[:block]}: #{Array(validation[:errors]).join('; ')}"
      end
    end

    log_validation_summary
  end

  def log_validation_summary
    return unless @validation_enabled

    total = @validation_stats.values.sum
    return if total == 0

    pass_rate = (@validation_stats[:passed].to_f / total * 100).round(2)

    logger.info "=" * 60
    logger.info "Validation Summary: #{@validation_stats[:passed]}/#{total} passed (#{pass_rate}%)"
    logger.info "  Passed: #{@validation_stats[:passed]}"
    logger.info "  Failed: #{@validation_stats[:failed]}"
    logger.info "=" * 60
  end

  public

  def validation_summary
    return nil unless @validation_enabled

    total = @validation_stats.values.sum
    pass_rate = total > 0 ? (@validation_stats[:passed].to_f / total * 100).round(2) : 0

    "Validation: #{@validation_stats[:passed]}/#{total} passed (#{pass_rate}%), " \
    "#{@validation_stats[:failed]} failed"
  end

  def shutdown
    @prefetcher&.shutdown

    if @validation_executor
      logger.info "Shutting down validation thread pool..."
      @validation_executor.shutdown
      if @validation_executor.wait_for_termination(10)
        logger.info "Validation thread pool shut down successfully"
      else
        logger.warn "Validation thread pool shutdown timed out, forcing kill"
        @validation_executor.kill
      end
    end
  end
end
