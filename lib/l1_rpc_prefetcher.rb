require 'concurrent'
require 'retriable'

class L1RpcPrefetcher
  def initialize(ethereum_client:,
                 ahead: ENV.fetch('L1_PREFETCH_FORWARD', Rails.env.test? ? 5 : 200).to_i,
                 threads: ENV.fetch('L1_PREFETCH_THREADS', Rails.env.test? ? 2 : 10).to_i)
    @eth = ethereum_client
    @ahead = ahead
    @threads = threads

    # Thread-safe collections and pool
    @pool = Concurrent::FixedThreadPool.new(threads)
    @promises = Concurrent::Map.new
  end

  def ensure_prefetched(from_block)
    to_block = from_block + @ahead
    # Only create promises for blocks we don't have yet
    blocks_to_fetch = (from_block..to_block).reject { |n| @promises.key?(n) }

    return if blocks_to_fetch.empty?

    # Only enqueue a reasonable number at once to avoid overwhelming the promise system
    # We'll enqueue more as blocks are consumed
    max_to_enqueue = [@threads * 20, 100].min  # At most 20x thread count or 100

    to_enqueue = blocks_to_fetch.first(max_to_enqueue)
    Rails.logger.debug "Enqueueing #{to_enqueue.size} of #{blocks_to_fetch.size} blocks: #{to_enqueue.first}..#{to_enqueue.last}"

    to_enqueue.each { |block_number| enqueue_single(block_number) }
  end

  def fetch(block_number)
    ensure_prefetched(block_number)

    # Get or create promise
    promise = @promises[block_number] || enqueue_single(block_number)

    # Wait for result - if it's already done, this returns immediately
    timeout = Rails.env.test? ? 5 : 30

    Rails.logger.debug "Fetching block #{block_number}, promise state: #{promise.state}"

    begin
      result = promise.value!(timeout)
      Rails.logger.debug "Got result for block #{block_number}"
      result
    rescue Concurrent::TimeoutError => e
      Rails.logger.error "Timeout fetching block #{block_number} after #{timeout}s"
      # Clean up on timeout
      @promises.delete(block_number)
      raise
    end
  end

  def clear_older_than(min_keep)
    # Memory management - remove old promises
    return if min_keep.nil?

    deleted = 0
    @promises.keys.each do |n|
      if n < min_keep
        @promises.delete(n)
        deleted += 1
      end
    end

    Rails.logger.debug "Cleared #{deleted} promises older than #{min_keep}" if deleted > 0
  end

  def stats
    total = @promises.size
    # Count fulfilled promises by iterating
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
      promises_total: total,
      promises_fulfilled: fulfilled,
      promises_pending: pending,
      threads_active: @pool.length,
      threads_queued: @pool.queue_length
    }
  end

  def shutdown
    @pool.shutdown
    if @pool.wait_for_termination(30)
      Rails.logger.info "L1 RPC Prefetcher thread pool shut down successfully"
    else
      Rails.logger.warn "L1 RPC Prefetcher shutdown timed out, forcing kill"
      @pool.kill
    end
  end

  private

  def enqueue_single(block_number)
    @promises.compute_if_absent(block_number) do
      Rails.logger.debug "Creating promise for block #{block_number}"

      Concurrent::Promise.execute(executor: @pool) do
        Rails.logger.debug "Executing fetch for block #{block_number}"
        fetch_job(block_number)
      end.rescue do |e|
        Rails.logger.error "Prefetch failed for block #{block_number}: #{e.message}"
        # Clean up failed promise so it can be retried
        @promises.delete(block_number)
        raise e
      end
    end
  end

  def fetch_job(block_number)
    # Use shared persistent client (thread-safe with Net::HTTP::Persistent)
    client = @eth

    Retriable.retriable(tries: 3, base_interval: 1, max_interval: 4) do
      block = client.get_block(block_number, true)
      receipts = client.get_transaction_receipts(block_number)

      eth_block = EthBlock.from_rpc_result(block)
      ethscriptions_block = EthscriptionsBlock.from_eth_block(eth_block)
      ethscription_txs = EthTransaction.ethscription_txs_from_rpc_results(block, receipts, ethscriptions_block)

      # Also prefetch Ethscriptions API data for validation if enabled
      api_data = nil
      if ENV['ETHSCRIPTIONS_API_VALIDATION_ENABLED'] == 'true'
        begin
          api_data = EthscriptionsApiClient.fetch_block_data(block_number)
          Rails.logger.debug "Prefetched API data for block #{block_number}"
        rescue => e
          # Log but don't fail - validation can handle missing API data
          Rails.logger.warn "Failed to prefetch API data for block #{block_number}: #{e.message}"
        end
      end

      {
        eth_block: eth_block,
        ethscriptions_block: ethscriptions_block,
        ethscription_txs: ethscription_txs,
        api_data: api_data  # Will be nil if disabled or failed
      }
    end
  end
end