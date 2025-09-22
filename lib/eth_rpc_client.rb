class EthRpcClient
  class HttpError < StandardError
    attr_reader :code, :http_message
    
    def initialize(code, http_message)
      @code = code
      @http_message = http_message
      super("HTTP error: #{code} #{http_message}")
    end
  end
  class ApiError < StandardError; end
  class ExecutionRevertedError < StandardError; end
  class MethodRequiredError < StandardError; end
  attr_accessor :base_url, :http

  def initialize(base_url = ENV['L1_RPC_URL'])
    self.base_url = base_url
    @uri = URI(base_url)
    @http = Net::HTTP::Persistent.new(
      name: "eth_rpc_#{@uri.host}:#{@uri.port}",
      pool_size: 100  # Increase pool size from default 64
    )
    @http.open_timeout = 10   # 10 seconds to establish connection
    @http.read_timeout = 30   # 30 seconds for slow eth_call operations
    @http.idle_timeout = 30   # Keep connections alive for 30 seconds
  end
  
  def self.l1
    @_l1_client ||= new(ENV.fetch('L1_RPC_URL'))
  end

  def self.l2
    @_l2_client ||= new(ENV.fetch('NON_AUTH_GETH_RPC_URL'))
  end

  def get_block(block_number, include_txs = false)
    if block_number.is_a?(String)
      return query_api(
        method: 'eth_getBlockByNumber',
        params: [block_number, include_txs]
      )
    end
    
    query_api(
      method: 'eth_getBlockByNumber',
      params: ['0x' + block_number.to_s(16), include_txs]
    )
  end
  
  def get_nonce(address, block_number = "latest")
    query_api(
      method: 'eth_getTransactionCount',
      params: [address, block_number]
    ).to_i(16)
  end
  
  def get_chain_id
    query_api(method: 'eth_chainId').to_i(16)
  end
  
  def trace_block(block_number)
    query_api(
      method: 'debug_traceBlockByNumber',
      params: ['0x' + block_number.to_s(16), { tracer: "callTracer", timeout: "10s" }]
    )
  end

  def trace_transaction(transaction_hash)
    query_api(
      method: 'debug_traceTransaction',
      params: [transaction_hash, { tracer: "callTracer", timeout: "10s" }]
    )
  end

  def trace(tx_hash)
    trace_transaction(tx_hash)
  end
  
  def get_transaction(transaction_hash)
    query_api(
      method: 'eth_getTransactionByHash',
      params: [transaction_hash]
    )
  end
  
  def get_transaction_receipts(block_number)
    if block_number.is_a?(String)
      return query_api(
        method: 'eth_getBlockReceipts',
        params: [block_number]
      )
    end
    
    query_api(
      method: 'eth_getBlockReceipts',
      params: ["0x" + block_number.to_s(16)]
    )
  end
  
  def get_block_receipts(block_number)
    get_transaction_receipts(block_number)
  end
  
  def get_transaction_receipt(transaction_hash)
    query_api(
      method: 'eth_getTransactionReceipt',
      params: [transaction_hash]
    )
  end
  
  def get_block_number
    query_api(method: 'eth_blockNumber').to_i(16)
  end

  def query_api(method = nil, params = [], **kwargs)
    if kwargs.present?
      method = kwargs[:method]
      params = kwargs[:params]
    end
    
    unless method
      raise MethodRequiredError, "Method is required"
    end
    
    data = {
      id: 1,
      jsonrpc: "2.0",
      method: method,
      params: params
    }

    url = base_url
    
    Retriable.retriable(
      tries: 7,
      base_interval: 1,
      max_interval: 32,
      multiplier: 2,
      rand_factor: 0.4,
      on: [Net::ReadTimeout, Net::OpenTimeout, HttpError, ApiError],
      on_retry: ->(exception, try, elapsed_time, next_interval) {
        Rails.logger.info "Retrying #{method} (attempt #{try}, next delay: #{next_interval.round(2)}s) - #{exception.message}"
      }
    ) do
      uri = URI(url)
      request = Net::HTTP::Post.new(uri)
      request.body = data.to_json
      headers.each { |key, value| request[key] = value }

      response = @http.request(uri, request)
      
      if response.code.to_i != 200
        raise HttpError.new(response.code.to_i, response.message)
      end

      parsed_response = JSON.parse(response.body, max_nesting: false)
      
      if parsed_response['error']
        error_message = parsed_response.dig('error', 'message') || 'Unknown API error'
        
        # Don't retry execution reverted errors as they're deterministic failures
        if error_message.include?('execution reverted')
          raise ExecutionRevertedError, "API error: #{error_message}"
        end
        
        raise ApiError, "API error: #{error_message}"
      end

      parsed_response['result']
    end
  end

  def call(method, params = [])
    query_api(method: method, params: params)
  end
  
  def eth_call(to:, data:, block_number: "latest")
    query_api(
      method: 'eth_call',
      params: [{ to: to, data: data }, block_number]
    )
  end
  
  def headers
    { 
      'Accept' => 'application/json',
      'Content-Type' => 'application/json'
    }
  end
  
  def get_code(address, block_number = "latest")
    query_api(
      method: 'eth_getCode',
      params: [address, block_number]
    )
  end

  def get_storage_at(address, slot, block_number = "latest")
    query_api(
      method: 'eth_getStorageAt',
      params: [address, slot, block_number]
    )
  end
end
