module TransactionHelper
  include Memery

  extend self
  
  def client
    GethDriver.client
  end
  
  def calculate_next_base_fee(prev_block_number)
    prev_block = get_block(prev_block_number)
    prev_block_gas_used = prev_block['gasUsed'].to_i(16)
    prev_block_gas_limit = prev_block['gasLimit'].to_i(16)
    prev_block_base_fee = prev_block['baseFeePerGas'].to_i(16)
  
    elasticity_multiplier = 2
    base_fee_change_denominator = 8
  
    parent_gas_target = prev_block_gas_limit / elasticity_multiplier
  
    if prev_block_gas_used == parent_gas_target
      return prev_block_base_fee
    end
  
    num = 0
    denom = parent_gas_target * base_fee_change_denominator
  
    if prev_block_gas_used > parent_gas_target
      num = prev_block_base_fee * (prev_block_gas_used - parent_gas_target)
      base_fee_delta = [num / denom, 1].max
      next_base_fee = prev_block_base_fee + base_fee_delta
    else
      num = prev_block_base_fee * (parent_gas_target - prev_block_gas_used)
      base_fee_delta = num / denom
      next_base_fee = [prev_block_base_fee - base_fee_delta, 0].max
    end
  
    next_base_fee
  end
  
  def get_block(number, get_transactions = false)
    if number.is_a?(String)
      return client.call("eth_getBlockByNumber", [number, get_transactions])
    end
    
    client.call("eth_getBlockByNumber", ["0x" + number.to_s(16), get_transactions])
  end
  
  def balance(address)
    client.call("eth_getBalance", [address, "latest"]).to_i(16)
  end
  
  def call(payload)
    client.call("eth_call", [payload, "latest"])
  end
  
  def code_at_address(address)
    client.call("eth_getCode", [address, "latest"])
  end
  
  def static_call(contract:, address:, function:, args:)
    function_obj = contract.parent.function_hash[function]
    data = function_obj.get_call_data(*args)
    
    result = GethDriver.non_auth_client.call("eth_call", [{
      to: address,
      data: data
    }, "latest"])
    
    function_obj.parse_result(result)
  end
  
  def get_function_calldata(
    contract:,
    function:,
    args:
  )
    proxy_contract = PredeployManager.get_contract_from_predeploy_info(name: "ERC1967Proxy")

    function_obj = contract.parent.function_hash[function] || proxy_contract.parent.function_hash[function]
    function_obj.get_call_data(*args).freeze
  end
  memoize :get_function_calldata
  
  def convert_args(contract, function_name, args)
    function = contract.functions.find { |f| f.name == function_name }
    inputs = function.inputs

    # If args is a string, treat it as a one-element array
    args = [args] if args.is_a?(String) || args.is_a?(Integer)

    # If args is a hash, convert it to an array based on the function inputs
    if args.is_a?(Hash)
      args_hash = args.with_indifferent_access
      args = inputs.map do |input|
        args_hash[input.name]
      end
    end

    # Ensure proper type conversion for uint and int types
    args = args&.each_with_index&.map do |arg_value, index|
      input = inputs[index]
      if arg_value.is_a?(String) && (input.type.starts_with?('uint') || input.type.starts_with?('int'))
        arg_value = Integer(arg_value, 10)
      end
      arg_value
    end

    args
  rescue => e
    binding.irb
    raise
  end
end
