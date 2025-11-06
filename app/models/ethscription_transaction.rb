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
  prop :transfer_ids, T.nilable(T::Array[String])  # Always an array, even for single transfers
  prop :transfer_from_address, T.nilable(String)
  prop :transfer_to_address, T.nilable(String)
  prop :enforced_previous_owner, T.nilable(String)

  # Unified source tracking
  prop :source_type, T.nilable(Symbol)  # :input or :event
  prop :source_index, T.nilable(Integer)

  # Debug info (can be removed if not needed)
  prop :ethscription_operation, T.nilable(String) # 'create', 'transfer', 'transfer_with_previous_owner'

  MAX_MIMETYPE_LENGTH = 1000
  DEPOSIT_TX_TYPE = 0x7D
  MINT = 0
  VALUE = 0
  GAS_LIMIT = 1_000_000_000
  TO_ADDRESS = SysConfig::ETHSCRIPTIONS_ADDRESS

  # Factory method for create operations
  def self.build_create_ethscription(
    eth_transaction:,
    creator:,
    initial_owner:,
    content_uri:,
    source_type:,
    source_index:
  )
    return unless DataUri.valid?(content_uri)

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

  # Transfer factory - handles single, multiple, and previous owner cases
  def self.build_transfer(
    eth_transaction:,
    from_address:,
    to_address:,
    source_type:,
    source_index:,
    ethscription_ids:,  # Can be a single ID or an array of IDs
    enforced_previous_owner: nil
  )
    # Normalize to array - accept either single ID or array of IDs
    ids = Array.wrap(ethscription_ids)

    # Determine operation type
    operation_type = enforced_previous_owner ? 'transfer_with_previous_owner' : 'transfer'

    new(
      from_address: Address20.from_hex(from_address.is_a?(String) ? from_address : from_address.to_hex),
      eth_transaction: eth_transaction,
      transfer_ids: ids,  # Always use array
      transfer_from_address: from_address,
      transfer_to_address: to_address,
      enforced_previous_owner: enforced_previous_owner,
      source_type: source_type&.to_sym,
      source_index: source_index,
      ethscription_operation: operation_type
    )
  end

  # Get function selector for this operation
  def function_selector
    function_signature = case ethscription_operation
    when 'create'
      'createEthscription((bytes32,bytes32,address,bytes,string,bool,(string,string,bytes)))'
    when 'transfer'
      if transfer_ids.length > 1
        'transferEthscriptions(address,bytes32[])'
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

  public

  # Dynamic input method - builds calldata on demand
  def input
    case ethscription_operation
    when 'create'
      ByteString.from_bin(build_create_calldata)
    when 'transfer'
      if transfer_ids.length > 1
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
    mimetype = data_uri.mimetype.to_s.first(MAX_MIMETYPE_LENGTH)
    raw_content = data_uri.decoded_data.b
    esip6 = DataUri.esip6?(content_uri) || false

    # Extract protocol params - returns [protocol, operation, encoded_data]
    # Pass the ethscription_id context so parsers can inject it when needed
    protocol, operation, encoded_data = ProtocolParser.for_calldata(
      content_uri,
      ethscription_id: eth_transaction.transaction_hash
    )
    
    # Hash the content for protocol uniqueness
    content_uri_hash_hex = Digest::SHA256.hexdigest(content_uri)
    content_uri_hash = [content_uri_hash_hex].pack('H*')

    # Convert hex strings to binary for ABI encoding
    tx_hash_bin = hex_to_bin(eth_transaction.transaction_hash)
    owner_bin = address_to_bin(initial_owner)

    # Build protocol params tuple
    protocol_params = [
      protocol,        # string protocol
      operation,       # string operation
      encoded_data     # bytes data
    ]

    # Encode parameters
    params = [
      tx_hash_bin,                            # bytes32 ethscriptionId (L1 tx hash)
      content_uri_hash,                        # bytes32 contentUriHash
      owner_bin,                               # address
      raw_content,                             # bytes content
      mimetype.b,                              # string
      esip6,                                   # bool esip6
      protocol_params                          # ProtocolParams tuple
    ]

    begin
      encoded = Eth::Abi.encode(
        ['(bytes32,bytes32,address,bytes,string,bool,(string,string,bytes))'],
        [params]
      )
    rescue Encoding::CompatibilityError => e
      Rails.logger.error "=== ABI Encoding Error (build_create_calldata) ==="
      Rails.logger.error "Error: #{e.message}"
      Rails.logger.error "content_uri: #{content_uri[0..100]}"
      Rails.logger.error "protocol: #{protocol.inspect[0..100]}, encoding: #{protocol.encoding.name}"
      Rails.logger.error "operation: #{operation.inspect[0..100]}, encoding: #{operation.encoding.name}"
      Rails.logger.error "encoded_data: #{encoded_data.inspect[0..100]}, encoding: #{encoded_data.encoding.name}, bytesize: #{encoded_data.bytesize}"
      Rails.logger.error "mimetype: #{mimetype.inspect}, encoding: #{mimetype.encoding.name}"
      Rails.logger.error "raw_content encoding: #{raw_content.encoding.name}, bytesize: #{raw_content.bytesize}"
      raise
    end

    # Ensure binary encoding
    (function_sig + encoded).b
  end

  def build_transfer_calldata
    # Get function selector as binary
    function_sig = function_selector.b

    # Convert to binary for ABI
    to_bin = address_to_bin(transfer_to_address)
    id_bin = hex_to_bin(transfer_ids.first)

    encoded = Eth::Abi.encode(['address', 'bytes32'], [to_bin, id_bin])

    # Ensure binary encoding
    (function_sig + encoded).b
  end

  def build_transfer_with_previous_owner_calldata
    # Get function selector as binary
    function_sig = function_selector.b

    # Convert to binary for ABI
    to_bin = address_to_bin(transfer_to_address)
    id_bin = hex_to_bin(transfer_ids.first)
    prev_bin = address_to_bin(enforced_previous_owner)

    encoded = Eth::Abi.encode(['address', 'bytes32', 'address'], [to_bin, id_bin, prev_bin])

    # Ensure binary encoding
    (function_sig + encoded).b
  end

  def build_transfer_multiple_calldata
    # Get function selector as binary
    function_sig = function_selector.b

    to_bin = address_to_bin(transfer_to_address)
    ids_bin = transfer_ids.map { |id| hex_to_bin(id) }

    encoded = Eth::Abi.encode(['address', 'bytes32[]'], [to_bin, ids_bin])

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
