class EthscriptionTransaction < T::Struct
  include SysConfig
  include AttrAssignable

  # Only what's needed for to_deposit_payload
  prop :from_address, T.nilable(Address20)

  # Block reference (used by importer)
  prop :ethscriptions_block, T.nilable(EthscriptionsBlock)

  # Operation data (for building calldata and validation)
  prop :eth_transaction, T.nilable(Object)

  # Create operation fields
  prop :creator, T.nilable(String)
  prop :initial_owner, T.nilable(String)
  prop :content_uri, T.nilable(String)

  # Transfer operation fields
  prop :ethscription_id, T.nilable(String)
  prop :transfer_ids, T.nilable(T::Array[String])
  prop :transfer_from_address, T.nilable(String)
  prop :transfer_to_address, T.nilable(String)
  prop :enforced_previous_owner, T.nilable(String)

  # Unified source tracking
  prop :source_type, T.nilable(Symbol)  # :input or :event
  prop :source_index, T.nilable(Integer)

  # Debug info (can be removed if not needed)
  prop :ethscription_operation, T.nilable(String) # 'create', 'transfer', 'transfer_with_previous_owner'

  DEPOSIT_TX_TYPE = 0x7D
  MINT = 0
  VALUE = 0
  GAS_LIMIT = 1_000_000_000
  TO_ADDRESS = SysConfig::ETHSCRIPTIONS_ADDRESS

  # Factory method for create operations
  def self.create_ethscription(
    eth_transaction:,
    creator:,
    initial_owner:,
    content_uri:,
    source_type:,
    source_index:
  )
    new(
      from_address: Address20.from_hex(creator.is_a?(String) ? creator : creator.to_hex),
      eth_transaction: eth_transaction,
      creator: creator,
      initial_owner: initial_owner,
      content_uri: content_uri,
      source_type: source_type&.to_sym,
      source_index: source_index,
      ethscription_operation: 'create'
    )
  end

  # Factory method for transfer operations
  def self.transfer_ethscription(
    eth_transaction:,
    from_address:,
    to_address:,
    ethscription_id:,
    enforced_previous_owner: nil,
    source_type:,
    source_index:
  )
    operation_type = enforced_previous_owner ? 'transfer_with_previous_owner' : 'transfer'

    new(
      from_address: Address20.from_hex(from_address.is_a?(String) ? from_address : from_address.to_hex),
      eth_transaction: eth_transaction,
      ethscription_id: ethscription_id,
      transfer_from_address: from_address,
      transfer_to_address: to_address,
      enforced_previous_owner: enforced_previous_owner,
      source_type: source_type&.to_sym,
      source_index: source_index,
      ethscription_operation: operation_type
    )
  end

  # Factory method for transferMultipleEthscriptions (inputs only)
  def self.transfer_multiple_ethscriptions(
    eth_transaction:,
    from_address:,
    to_address:,
    ethscription_ids:,
    source_type:,
    source_index:
  )
    new(
      from_address: Address20.from_hex(from_address.is_a?(String) ? from_address : from_address.to_hex),
      eth_transaction: eth_transaction,
      transfer_ids: ethscription_ids,
      transfer_from_address: from_address,
      transfer_to_address: to_address,
      source_type: source_type&.to_sym,
      source_index: source_index,
      ethscription_operation: 'transfer'
    )
  end

  # Get function selector for this operation
  def function_selector
    function_signature = case ethscription_operation
    when 'create'
      'createEthscription((bytes32,bytes32,address,bytes,string,string,string,bool,(string,string,string,uint256,uint256,uint256)))'
    when 'transfer'
      if transfer_ids && transfer_ids.any?
        'transferMultipleEthscriptions(bytes32[],address)'
      else
        'transferEthscription(address,bytes32)'
      end
    when 'transfer_with_previous_owner'
      'transferEthscriptionForPreviousOwner(address,bytes32,address)'
    else
      raise "Unknown ethscription operation: #{ethscription_operation}"
    end

    Eth::Util.keccak256(function_signature)[0...4]
  end

  # Unified source hash computation following Optimism pattern
  def source_hash
    raise "Operation must have source metadata" if source_type.nil? || source_index.nil?

    source_tag = source_type.to_s  # "input" or "event"
    source_tag_hash = Eth::Util.keccak256(source_tag.bytes.pack('C*'))  # Hash for constant width

    payload = ByteString.from_bin(
      eth_transaction.block_hash.to_bin +
      source_tag_hash +                    # 32 bytes (hashed source tag)
      function_selector +                   # 4 bytes (function selector)
      Eth::Util.zpad_int(source_index, 32)       # 32 bytes (source_index)
    )

    bin_val = Eth::Util.keccak256(
      Eth::Util.zpad_int(0, 32) + Eth::Util.keccak256(payload.to_bin)  # Domain 0 like Optimism
    )

    Hash32.from_bin(bin_val)
  end

  def valid_create?
    content_uri.present? &&
    creator.present? &&
    initial_owner.present? &&
    DataUri.valid?(content_uri)
  end

  def valid_transfer?
    # Basic field validation - if we extracted the data properly, ABI encoding should work
    case ethscription_operation
    when 'transfer'
      if transfer_ids
        # Multiple transfer (input-based)
        transfer_ids.is_a?(Array) && transfer_ids.any?
      else
        # Single transfer (event-based)
        ethscription_id.present?
      end
    when 'transfer_with_previous_owner'
      # Always single transfer (event-based only)
      ethscription_id.present?
    else
      false
    end &&
    transfer_from_address.present? &&
    transfer_to_address.present?
  end

  public

  # Dynamic input method - builds calldata on demand
  def input
    case ethscription_operation
    when 'create'
      ByteString.from_bin(build_create_calldata)
    when 'transfer'
      if transfer_ids && transfer_ids.any?
        ByteString.from_bin(build_transfer_multiple_calldata)
      else
        ByteString.from_bin(build_transfer_calldata)
      end
    when 'transfer_with_previous_owner'
      ByteString.from_bin(build_transfer_with_previous_owner_calldata)
    else
      raise "Unknown ethscription operation: #{ethscription_operation}"
    end
  end

  # Method for deposit payload generation (used by GethDriver)
  sig { returns(ByteString) }
  def to_deposit_payload
    tx_data = []
    tx_data.push(source_hash.to_bin)
    tx_data.push(from_address.to_bin)
    tx_data.push(TO_ADDRESS.to_bin)
    tx_data.push(Eth::Util.serialize_int_to_big_endian(MINT))
    tx_data.push(Eth::Util.serialize_int_to_big_endian(VALUE))
    tx_data.push(Eth::Util.serialize_int_to_big_endian(GAS_LIMIT))
    tx_data.push('')
    tx_data.push(input.to_bin)
    tx_encoded = Eth::Rlp.encode(tx_data)

    tx_type = Eth::Util.serialize_int_to_big_endian(DEPOSIT_TX_TYPE)
    ByteString.from_bin("#{tx_type}#{tx_encoded}")
  end

  # Build calldata for create operations (same for both input and event-based)
  def build_create_calldata
    # Get function selector as binary
    function_sig = function_selector.b

    # Both input and event-based creates use data URI format
    # Events are "equivalent of an EOA hex-encoding contentURI and putting it in the calldata"
    data_uri = DataUri.new(content_uri)
    mimetype = data_uri.mimetype.to_s
    media_type = mimetype&.split('/')&.first
    mime_subtype = mimetype&.split('/')&.last
    raw_content = data_uri.decoded_data.b
    esip6 = DataUri.esip6?(content_uri) || false
    token_params = TokenParamsExtractor.extract(content_uri)

    # Hash the content for protocol uniqueness
    content_uri_hash_hex = Digest::SHA256.hexdigest(content_uri)
    content_uri_hash = [content_uri_hash_hex].pack('H*')

    # Convert hex strings to binary for ABI encoding
    tx_hash_bin = hex_to_bin(eth_transaction.transaction_hash)
    owner_bin = address_to_bin(initial_owner)

    # Encode parameters
    params = [
      tx_hash_bin,                            # bytes32 transactionHash
      content_uri_hash,                        # bytes32 contentUriHash
      owner_bin,                               # address
      raw_content,                             # bytes content
      mimetype.b,                              # string
      media_type.to_s.b,                       # string
      mime_subtype.to_s.b,                     # string
      esip6,                                   # bool esip6
      token_params                             # TokenParams tuple
    ]

    encoded = Eth::Abi.encode(
      ['(bytes32,bytes32,address,bytes,string,string,string,bool,(string,string,string,uint256,uint256,uint256))'],
      [params]
    )

    # Ensure binary encoding
    (function_sig + encoded).b
  end

  def build_transfer_calldata
    # Get function selector as binary
    function_sig = function_selector.b

    # Convert to binary for ABI
    to_bin = address_to_bin(transfer_to_address)
    id_bin = hex_to_bin(ethscription_id)

    encoded = Eth::Abi.encode(['address', 'bytes32'], [to_bin, id_bin])

    # Ensure binary encoding
    (function_sig + encoded).b
  end

  def build_transfer_with_previous_owner_calldata
    # Get function selector as binary
    function_sig = function_selector.b

    # Convert to binary for ABI
    to_bin = address_to_bin(transfer_to_address)
    id_bin = hex_to_bin(ethscription_id)
    prev_bin = address_to_bin(enforced_previous_owner)

    encoded = Eth::Abi.encode(['address', 'bytes32', 'address'], [to_bin, id_bin, prev_bin])

    # Ensure binary encoding
    (function_sig + encoded).b
  end

  def build_transfer_multiple_calldata
    # Get function selector as binary
    function_sig = function_selector.b

    ids_bin = (transfer_ids || []).map { |id| hex_to_bin(id) }
    to_bin = address_to_bin(transfer_to_address)

    encoded = Eth::Abi.encode(['bytes32[]', 'address'], [ids_bin, to_bin])

    (function_sig + encoded).b
  end

  # Helper to convert hex string to binary
  def hex_to_bin(hex_str)
    return nil unless hex_str
    # Hash32 objects have .to_bin, strings need conversion
    hex_str.respond_to?(:to_bin) ? hex_str.to_bin : [hex_str.delete_prefix('0x')].pack('H*')
  end

  # Helper to convert address to binary (20 bytes)
  def address_to_bin(addr_str)
    return nil unless addr_str
    # Handle Address20 objects that have .to_bin method
    if addr_str.respond_to?(:to_bin)
      return addr_str.to_bin
    end

    clean_hex = addr_str.to_s.delete_prefix('0x')
    # Ensure 20 bytes (40 hex chars)
    clean_hex = clean_hex.rjust(40, '0')[-40..]
    [clean_hex].pack('H*')
  end
end
