require 'net/http/persistent'
require 'json'

class PooledRpcClient
  class RpcError < StandardError; end

  MAX_RETRIES = 3
  RETRY_DELAY = 0.5

  attr_reader :base_url

  def initialize(base_url:, api_key: nil, pool_size: 20)
    @base_url = base_url.chomp('/')
    @api_key = api_key

    url = [@base_url, @api_key].compact.join('/')
    @uri = URI.parse(url)

    @http = Net::HTTP::Persistent.new(name: "eth_rpc_#{@uri.host}", pool_size: pool_size)
    @http.open_timeout = 5
    @http.read_timeout = 15
    @http.idle_timeout = 30

    @request_id = Concurrent::AtomicFixnum.new(0)
  end

  def get_block(block_number)
    query_api(
      method: 'eth_getBlockByNumber',
      params: ['0x' + block_number.to_s(16), true]
    )
  end

  def get_transaction_receipts(block_number, **_options)
    result = query_api(
      method: 'eth_getBlockReceipts',
      params: ['0x' + block_number.to_s(16)]
    )['result']

    {
      'id' => 1,
      'jsonrpc' => '2.0',
      'result' => {
        'receipts' => result
      }
    }
  end

  def get_block_number
    query_api(method: 'eth_blockNumber')['result'].to_i(16)
  end

  private

  def query_api(method:, params: [])
    retries = 0

    begin
      request = Net::HTTP::Post.new(@uri.request_uri)
      request['Content-Type'] = 'application/json'
      request['Accept'] = 'application/json'
      request.body = {
        id: @request_id.increment,
        jsonrpc: '2.0',
        method: method,
        params: params
      }.to_json

      response = @http.request(@uri, request)
      result = JSON.parse(response.body)

      if result['error']
        raise RpcError, "RPC error: #{result['error']['message']} (code: #{result['error']['code']})"
      end

      result
    rescue Net::HTTP::Persistent::Error, Errno::ECONNRESET, Errno::ETIMEDOUT,
           Errno::ECONNREFUSED, SocketError, Timeout::Error, RpcError => e
      retries += 1
      if retries <= MAX_RETRIES
        sleep(RETRY_DELAY * retries)
        retry
      end
      Rails.logger.error "[PooledRpcClient] #{method} failed after #{MAX_RETRIES} retries: #{e.class} - #{e.message}"
      raise
    rescue JSON::ParserError => e
      Rails.logger.error "[PooledRpcClient] Invalid JSON response: #{e.message}"
      raise
    end
  end
end
