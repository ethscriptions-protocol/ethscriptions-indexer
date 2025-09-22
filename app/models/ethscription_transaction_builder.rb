class EthscriptionTransactionBuilder
  include SysConfig

  # Event signatures
  ESIP1_SIG = '0x' + Eth::Util.keccak256('ethscriptions_protocol_TransferEthscription(address,bytes32)').unpack1('H*')
  ESIP2_SIG = '0x' + Eth::Util.keccak256('ethscriptions_protocol_TransferEthscriptionForPreviousOwner(address,address,bytes32)').unpack1('H*')
  CREATE_SIG = '0x' + Eth::Util.keccak256('ethscriptions_protocol_CreateEthscription(address,string)').unpack1('H*')

  # Build deposit transactions from an L1 transaction
  def self.build_deposits(eth_transaction, ethscriptions_block)
    new(eth_transaction, ethscriptions_block).build_transactions
  end

  def initialize(eth_transaction, ethscriptions_block)
    @eth_tx = eth_transaction
    @ethscriptions_block = ethscriptions_block
    @transactions = []
  end

  def build_transactions
    # Only process successful transactions
    return [] unless @eth_tx.status == 1

    # 1. Check for creation (from input or events)
    detect_creation

    # 2. Process transfers via input (single transfers from genesis, multi from ESIP-5)
    process_input_transfers

    # 3. Process transfers via events (ESIP-1/2)
    process_event_transfers

    @transactions
  end

  private

  def detect_creation
    # Try to create from input
    content = decoded_input
    if @eth_tx.to_address.present? && content
      transaction = EthscriptionTransaction.create_ethscription(
        eth_transaction: @eth_tx,
        creator: normalize_address(@eth_tx.from_address),
        initial_owner: normalize_address(@eth_tx.to_address),
        content_uri: content,
        source_type: :input,
        source_index: @eth_tx.transaction_index
      )

      @transactions << transaction if transaction.valid_create?
    end

    # Also check for create events (ESIP-3)
    if SysConfig.esip3_enabled?(@eth_tx.block_number) && @eth_tx.logs
      process_create_events
    end
  end

  def process_create_events
    ordered_events.each do |log|
      next unless log['topics']&.first == CREATE_SIG

      begin
        # Exact topic length match like original
        next unless log['topics'].length == 2

        # Decode exactly like the original
        initial_owner = Eth::Abi.decode(['address'], log['topics'].second).first
        content_uri_data = Eth::Abi.decode(['string'], log['data']).first
        content_uri = HexDataProcessor.clean_utf8(content_uri_data)

        transaction = EthscriptionTransaction.create_ethscription(
          eth_transaction: @eth_tx,
          creator: normalize_address(log['address']),
          initial_owner: normalize_address(initial_owner),
          content_uri: content_uri,
          source_type: :event,
          source_index: log['logIndex'].to_i(16)
        )

        @transactions << transaction if transaction.valid_create?
      rescue Eth::Abi::DecodingError => e
        Rails.logger.error "Failed to decode create event: #{e.message}"
        next
      end
    end
  end

  def process_input_transfers
    return unless @eth_tx.to_address.present?

    # ByteString to hex conversion
    input_hex = @eth_tx.input.to_hex.delete_prefix('0x')

    # Check for valid transfer input
    # Single transfers (64 chars) supported from genesis
    # Multi transfers (n*64 chars) supported from ESIP-5
    valid_length = if SysConfig.esip5_enabled?(@eth_tx.block_number)
      # ESIP-5: Allow multiple transfers
      input_hex.length > 0 && input_hex.length % 64 == 0
    else
      # Pre-ESIP-5: Only single transfers (exactly 64 hex chars)
      input_hex.length == 64
    end

    return unless valid_length

    # Parse all 32-byte hashes for a single multi-transfer call
    ids = input_hex.scan(/.{64}/).map { |hash_hex| normalize_hash("0x#{hash_hex}") }
    return if ids.empty?

    transaction = EthscriptionTransaction.transfer_multiple_ethscriptions(
      eth_transaction: @eth_tx,
      from_address: normalize_address(@eth_tx.from_address),
      to_address: normalize_address(@eth_tx.to_address),
      ethscription_ids: ids,
      source_type: :input,
      source_index: @eth_tx.transaction_index
    )

    @transactions << transaction
  end

  def process_event_transfers
    ordered_events.each do |log|
      begin
        case log['topics']&.first
        when ESIP1_SIG
          handle_esip1_event(log) if SysConfig.esip1_enabled?(@eth_tx.block_number)
        when ESIP2_SIG
          handle_esip2_event(log) if SysConfig.esip2_enabled?(@eth_tx.block_number)
        end
      rescue Eth::Abi::DecodingError => e
        Rails.logger.error "Failed to decode transfer event: #{e.message}"
        next
      end
    end
  end

  def handle_esip1_event(log)
    # Exact topic length match like original
    return unless log['topics'].length == 3

    # Decode exactly like the original
    event_to = Eth::Abi.decode(['address'], log['topics'].second).first
    tx_hash = Eth::Util.bin_to_prefixed_hex(
      Eth::Abi.decode(['bytes32'], log['topics'].third).first
    )

    ethscription_id = normalize_hash(tx_hash)

    transaction = EthscriptionTransaction.transfer_ethscription(
      eth_transaction: @eth_tx,
      from_address: normalize_address(log['address']),
      to_address: normalize_address(event_to),
      ethscription_id: ethscription_id,
      source_type: :event,
      source_index: log['logIndex'].to_i(16)
    )

    @transactions << transaction
  end

  def handle_esip2_event(log)
    # Exact topic length match like original
    return unless log['topics'].length == 4

    # Decode exactly like the original
    event_previous_owner = Eth::Abi.decode(['address'], log['topics'].second).first
    event_to = Eth::Abi.decode(['address'], log['topics'].third).first
    tx_hash = Eth::Util.bin_to_prefixed_hex(
      Eth::Abi.decode(['bytes32'], log['topics'].fourth).first
    )

    ethscription_id = normalize_hash(tx_hash)

    transaction = EthscriptionTransaction.transfer_ethscription(
      eth_transaction: @eth_tx,
      from_address: normalize_address(log['address']),
      to_address: normalize_address(event_to),
      ethscription_id: ethscription_id,
      enforced_previous_owner: normalize_address(event_previous_owner),
      source_type: :event,
      source_index: log['logIndex'].to_i(16)
    )

    @transactions << transaction
  end

  def ordered_events
    # Handle nil or missing logs gracefully
    return [] if @eth_tx.logs.nil?

    @eth_tx.logs.reject { |log| log['removed'] }
                .sort_by { |log| log['logIndex'].to_i(16) }
  end

  def decoded_input
    HexDataProcessor.hex_to_utf8(
      @eth_tx.input.to_hex,
      support_gzip: SysConfig.esip7_enabled?(@eth_tx.block_number)
    )
  end

  def normalize_address(addr)
    return nil unless addr
    # Handle both Address20 objects and strings
    addr_str = addr.respond_to?(:to_hex) ? addr.to_hex : addr.to_s
    addr_str.downcase
  end

  def normalize_hash(hash)
    return nil unless hash
    # Handle both Hash32 objects and strings
    hash_str = hash.respond_to?(:to_hex) ? hash.to_hex : hash.to_s
    hash_str.downcase
  end

end
