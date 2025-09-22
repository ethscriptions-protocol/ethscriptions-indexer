class GethClient
  class ClientError < StandardError; end
  
  attr_reader :node_url, :jwt_secret, :http

  def initialize(node_url)
    @node_url = node_url
    @jwt_secret = ENV.fetch('JWT_SECRET')
    @http = Net::HTTP::Persistent.new(name: "geth_client_#{node_url}")
  end

  def call(command, args = [])
    payload = {
      jsonrpc: "2.0",
      method: command,
      params: args,
      id: 1
    }
    
    # Benchmark.msr("Call: #{command}") do
      send_request(payload)
    # end
  end
  alias :send_command :call

  sig { params(l2_block_number: Integer).returns(Hash) }
  def get_l1_attributes(l2_block_number)
    if l2_block_number > 0
      l2_block = EthRpcClient.l2.call("eth_getBlockByNumber", ["0x#{l2_block_number.to_s(16)}", true])
      l2_attributes_tx = l2_block['transactions'].first
      L1AttributesTxCalldata.decode(
        ByteString.from_hex(l2_attributes_tx['input']),
        l2_block_number
      )
    else
      l1_block = EthRpcClient.l1.get_block(SysConfig.l1_genesis_block_number)
      eth_block = EthBlock.from_rpc_result(l1_block)
      {
        timestamp: eth_block.timestamp,
        number: eth_block.number,
        base_fee: eth_block.base_fee_per_gas,
        blob_base_fee: 1,
        hash: eth_block.block_hash,
        batcher_hash: Hash32.from_bin("\x00".b * 32),
        sequence_number: 0,
        base_fee_scalar: 0,
        blob_base_fee_scalar: 1
      }.with_indifferent_access
    end
  end
  
  def send_request(payload)
    uri = URI(@node_url)
    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request['Authorization'] = "Bearer #{jwt}"
    request.body = payload.to_json

    response = @http.request(uri, request)

    unless response.code.to_i == 200
      raise ClientError, response
    end

    parsed_response = JSON.parse(response.body)
    
    if parsed_response['error']
      raise ClientError.new(parsed_response['error'])
    end

    parsed_response['result']
  end

  def jwt_payload
    {
      iat: current_time.to_i
    }
  end

  def current_time
    Time.zone.now
  end
  
  def jwt
    JWT.encode(jwt_payload, ByteString.from_hex(jwt_secret).to_bin, 'HS256')
  end

  def shutdown
    @http.shutdown
  end
end
