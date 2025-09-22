class L1AttributesTransaction < T::Struct
  include SysConfig
  include AttrAssignable

  # Only what's needed for to_deposit_payload
  prop :source_hash, T.nilable(Hash32)
  prop :from_address, T.nilable(Address20)
  prop :input, T.nilable(ByteString)

  # Constants
  DEPOSIT_TX_TYPE = 0x7D
  MINT = 0
  VALUE = 0
  GAS_LIMIT = 1_000_000_000

  # L1 attributes transactions always go to L1_INFO_ADDRESS
  def to_address
    L1_INFO_ADDRESS
  end

  # Factory method for L1 attributes transactions
  def self.from_ethscriptions_block(ethscriptions_block)
    calldata = L1AttributesTxCalldata.build(ethscriptions_block)

    payload = [
      ethscriptions_block.eth_block_hash.to_bin,
      Eth::Util.zpad_int(ethscriptions_block.sequence_number, 32)
    ].join

    source_hash = compute_source_hash(
      ByteString.from_bin(payload),
      1
    )

    new(
      source_hash: source_hash,
      from_address: SYSTEM_ADDRESS,
      input: calldata
    )
  end

  sig { params(payload: ByteString, source_domain: Integer).returns(Hash32) }
  def self.compute_source_hash(payload, source_domain)
    bin_val = Eth::Util.keccak256(
      Eth::Util.zpad_int(source_domain, 32) +
      Eth::Util.keccak256(payload.to_bin)
    )

    Hash32.from_bin(bin_val)
  end

  # Method for deposit payload generation (used by GethDriver)
  sig { returns(ByteString) }
  def to_deposit_payload
    tx_data = []
    tx_data.push(source_hash.to_bin)
    tx_data.push(from_address.to_bin)
    tx_data.push(to_address.to_bin)
    tx_data.push(Eth::Util.serialize_int_to_big_endian(MINT))
    tx_data.push(Eth::Util.serialize_int_to_big_endian(VALUE))
    tx_data.push(Eth::Util.serialize_int_to_big_endian(GAS_LIMIT))
    tx_data.push('')
    tx_data.push(input.to_bin)
    tx_encoded = Eth::Rlp.encode(tx_data)

    tx_type = Eth::Util.serialize_int_to_big_endian(DEPOSIT_TX_TYPE)
    ByteString.from_bin("#{tx_type}#{tx_encoded}")
  end
end