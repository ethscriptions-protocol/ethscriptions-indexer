module L1AttributesTxCalldata
  extend self
  
  FUNCTION_SELECTOR = Eth::Util.keccak256('setL1BlockValuesEcotone()').first(4)
  
  sig { params(ethscriptions_block: EthscriptionsBlock).returns(ByteString) }
  def build(ethscriptions_block)
    base_fee_scalar = 0
    blob_base_fee_scalar = 1 # TODO: use real values
    blob_base_fee = 1
    batcher_hash = "\x00" * 32
    
    packed_data = [
      FUNCTION_SELECTOR,
      Eth::Util.zpad_int(base_fee_scalar, 4),
      Eth::Util.zpad_int(blob_base_fee_scalar, 4),
      Eth::Util.zpad_int(ethscriptions_block.sequence_number, 8),
      Eth::Util.zpad_int(ethscriptions_block.eth_block_timestamp, 8),
      Eth::Util.zpad_int(ethscriptions_block.eth_block_number, 8),
      Eth::Util.zpad_int(ethscriptions_block.eth_block_base_fee_per_gas, 32),
      Eth::Util.zpad_int(blob_base_fee, 32),
      ethscriptions_block.eth_block_hash.to_bin,
      batcher_hash
    ]
    
    ByteString.from_bin(packed_data.join)
  end
  
  sig { params(calldata: ByteString, block_number: Integer).returns(T::Hash[Symbol, T.untyped]) }
  def decode(calldata, block_number)
    data = calldata.to_bin
  
    # Remove the function selector
    data = data[4..-1]
    
    # Unpack the data
    base_fee_scalar = data[0...4].unpack1('N')
    blob_base_fee_scalar = data[4...8].unpack1('N')
    sequence_number = data[8...16].unpack1('Q>')
    timestamp = data[16...24].unpack1('Q>')
    number = data[24...32].unpack1('Q>')
    base_fee = data[32...64].unpack1('H*').to_i(16)
    blob_base_fee = data[64...96].unpack1('H*').to_i(16)
    hash = data[96...128].unpack1('H*')
    batcher_hash = data[128...160].unpack1('H*')
    
    {
      timestamp: timestamp,
      number: number,
      base_fee: base_fee,
      blob_base_fee: blob_base_fee,
      hash: Hash32.from_hex("0x#{hash}"),
      batcher_hash: Hash32.from_hex("0x#{batcher_hash}"),
      sequence_number: sequence_number,
      blob_base_fee_scalar: blob_base_fee_scalar,
      base_fee_scalar: base_fee_scalar
    }.with_indifferent_access
  end
end