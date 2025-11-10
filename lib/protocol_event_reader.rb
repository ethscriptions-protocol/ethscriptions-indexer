# Utility for reading protocol events from L2 transaction receipts
class ProtocolEventReader
  # Event signatures from contracts
  EVENT_SIGNATURES = {
    # Ethscriptions.sol events
    'EthscriptionCreated' => 'EthscriptionCreated(bytes32,address,address,bytes32,bytes32,uint256)',
    'Transfer' => 'Transfer(address,address,uint256)',
    'ProtocolHandlerSuccess' => 'ProtocolHandlerSuccess(bytes32,string,bytes)',
    'ProtocolHandlerFailed' => 'ProtocolHandlerFailed(bytes32,string,bytes)',

    # ERC20FixedDenominationManager.sol events
    'ERC20FixedDenominationTokenDeployed' => 'ERC20FixedDenominationTokenDeployed(bytes32,address,string,uint256,uint256)',
    'ERC20FixedDenominationTokenMinted' => 'ERC20FixedDenominationTokenMinted(bytes32,address,uint256,uint256,bytes32)',
    'ERC20FixedDenominationTokenTransferred' => 'ERC20FixedDenominationTokenTransferred(bytes32,address,address,uint256,uint256,bytes32)',
    'ERC721CollectionDeployed' => 'ERC721CollectionDeployed(bytes32,address,string)',

    # CollectionsManager.sol events
    # CollectionsManager.sol events (match actual signatures)
    'CollectionCreated' => 'CollectionCreated(bytes32,address,string,string,uint256)',
    'ItemsAdded' => 'ItemsAdded(bytes32,uint256,bytes32)',
    'ItemsRemoved' => 'ItemsRemoved(bytes32,uint256,bytes32)',
    'CollectionEdited' => 'CollectionEdited(bytes32)',
    'CollectionLocked' => 'CollectionLocked(bytes32)',
    'OwnershipTransferred' => 'OwnershipTransferred(bytes32,address,address)'
  }.freeze

  def self.parse_receipt_events(receipt)
    return [] if receipt.nil?

    # Convert to HashWithIndifferentAccess to handle both symbol and string keys
    receipt = ActiveSupport::HashWithIndifferentAccess.new(receipt) if defined?(ActiveSupport)

    return [] if receipt['logs'].nil?

    events = []

    receipt['logs'].each do |log|
      event = parse_log(log)
      events << event if event
    end

    events
  end

  def self.parse_log(log)
    # Convert to HashWithIndifferentAccess to handle both symbol and string keys
    log = ActiveSupport::HashWithIndifferentAccess.new(log) if defined?(ActiveSupport)

    return nil if log['topics'].nil? || log['topics'].empty?

    # First topic is always the event signature hash
    event_signature_hash = log['topics'][0]

    # Find matching event
    event_name = find_event_by_signature_hash(event_signature_hash)
    return nil unless event_name

    # Parse based on event type
    case event_name
    when 'ProtocolHandlerSuccess'
      parse_protocol_handler_success(log)
    when 'ProtocolHandlerFailed'
      parse_protocol_handler_failed(log)
    when 'ERC20FixedDenominationTokenDeployed', 'FixedFungibleTokenDeployed'
      parse_erc20_fixed_denomination_token_deployed(log)
    when 'ERC20FixedDenominationTokenMinted', 'FixedFungibleTokenMinted'
      parse_erc20_fixed_denomination_token_minted(log)
    when 'ERC20FixedDenominationTokenTransferred', 'FixedFungibleTokenTransferred'
      parse_erc20_fixed_denomination_token_transferred(log)
    when 'ERC721CollectionDeployed'
      parse_erc721_collection_deployed(log)
    when 'CollectionCreated'
      parse_collection_created(log)
    when 'ItemsAdded'
      parse_items_added(log)
    when 'ItemsRemoved'
      parse_items_removed(log)
    when 'CollectionEdited'
      parse_collection_edited(log)
    else
      {
        event: event_name,
        raw: log
      }
    end
  end

  private

  def self.find_event_by_signature_hash(hash)
    EVENT_SIGNATURES.find do |name, signature|
      computed_hash = '0x' + Eth::Util.keccak256(signature).unpack1('H*')
      computed_hash.downcase == hash.downcase
    end&.first
  end

  def self.parse_protocol_handler_success(log)
    # ProtocolHandlerSuccess(bytes32 indexed txHash, string protocol, bytes returnData)
    tx_hash = log['topics'][1] # indexed parameter

    # Decode non-indexed data
    # The data contains string protocol and bytes returnData parameters
    if log['data'] && log['data'] != '0x'
      data_hex = log['data'].delete_prefix('0x')
      # Handle empty or very short data
      if data_hex.length < 128  # Minimum for offset (32 bytes) + length (32 bytes)
        return {
          event: 'ProtocolHandlerSuccess',
          tx_hash: tx_hash,
          protocol: '',
          return_data: '0x'
        }
      end

      data = [data_hex].pack('H*')
      decoded = Eth::Abi.decode(['string', 'bytes'], data)

      {
        event: 'ProtocolHandlerSuccess',
        tx_hash: tx_hash,
        protocol: decoded[0],
        return_data: '0x' + decoded[1].unpack1('H*')
      }
    else
      {
        event: 'ProtocolHandlerSuccess',
        tx_hash: tx_hash,
        protocol: '',
        return_data: '0x'
      }
    end
  rescue => e
    Rails.logger.error "Failed to parse ProtocolHandlerSuccess: #{e.message}"
    # Return partial result instead of nil so event is still recognized
    {
      event: 'ProtocolHandlerSuccess',
      tx_hash: log['topics'][1],
      protocol: 'parse_error',
      return_data: '0x'
    }
  end

  def self.parse_protocol_handler_failed(log)
    # ProtocolHandlerFailed(bytes32 indexed txHash, string protocol, bytes reason)
    tx_hash = log['topics'][1]

    if log['data'] && log['data'] != '0x'
      data_hex = log['data'].delete_prefix('0x')
      # Handle empty or very short data
      if data_hex.length < 128  # Minimum for offset (32 bytes) + offset (32 bytes) + length (32 bytes) + length (32 bytes)
        return {
          event: 'ProtocolHandlerFailed',
          tx_hash: tx_hash,
          protocol: '',
          reason: 'parse_error'
        }
      end

      data = [data_hex].pack('H*')
      decoded = Eth::Abi.decode(['string', 'bytes'], data)

      # The bytes reason is actually an ABI-encoded error string
      # Try to decode it as a revert string
      reason_bytes = decoded[1]
      reason = if reason_bytes && reason_bytes.length > 0
        # Try to decode as Error(string)
        if reason_bytes.start_with?("\x08\xC3y\xA0".b)  # Error(string) selector
          # Skip the selector (4 bytes) and decode the string
          begin
            Eth::Abi.decode(['string'], reason_bytes[4..-1])[0]
          rescue
            # If decode fails, just use the raw bytes
            reason_bytes
          end
        else
          reason_bytes
        end
      else
        'unknown'
      end

      {
        event: 'ProtocolHandlerFailed',
        tx_hash: tx_hash,
        protocol: decoded[0],
        reason: reason
      }
    else
      {
        event: 'ProtocolHandlerFailed',
        tx_hash: tx_hash,
        protocol: '',
        reason: 'no_data'
      }
    end
  rescue => e
    Rails.logger.error "Failed to parse ProtocolHandlerFailed: #{e.message}"
    # Return partial result instead of nil so event is still recognized
    {
      event: 'ProtocolHandlerFailed',
      tx_hash: log['topics'][1],
      protocol: 'parse_error',
      reason: e.message
    }
  end

  def self.parse_erc20_fixed_denomination_token_deployed(log)
    # ERC20FixedDenominationTokenDeployed(bytes32 indexed deployTxHash, address indexed tokenAddress, string tick, uint256 maxSupply, uint256 mintAmount)
    deploy_tx_hash = log['topics'][1]
    token_address = '0x' + log['topics'][2][-40..] if log['topics'][2]  # Last 20 bytes of topic

    data = [log['data'].delete_prefix('0x')].pack('H*')
    decoded = Eth::Abi.decode(['string', 'uint256', 'uint256'], data)

    {
      event: 'ERC20FixedDenominationTokenDeployed',
      deploy_tx_hash: deploy_tx_hash,
      token_contract: token_address,
      tick: decoded[0],
      max_supply: decoded[1],
      mint_amount: decoded[2]
    }
  rescue => e
    Rails.logger.error "Failed to parse ERC20FixedDenominationTokenDeployed: #{e.message}"
    nil
  end

  def self.parse_erc20_fixed_denomination_token_minted(log)
    # ERC20FixedDenominationTokenMinted(bytes32 indexed deployEthscriptionId, address indexed to, uint256 amount, uint256 mintId, bytes32 ethscriptionId)
    deploy_tx_hash = log['topics'][1]
    to_address = '0x' + log['topics'][2][-40..] if log['topics'][2]  # Last 20 bytes

    data = [log['data'].delete_prefix('0x')].pack('H*')
    decoded = Eth::Abi.decode(['uint256', 'uint256', 'bytes32'], data)

    {
      event: 'ERC20FixedDenominationTokenMinted',
      deploy_tx_hash: deploy_tx_hash,
      to: to_address,
      amount: decoded[0],
      mint_id: decoded[1],
      ethscription_tx_hash: '0x' + decoded[2].unpack1('H*')
    }
  rescue => e
    Rails.logger.error "Failed to parse ERC20FixedDenominationTokenMinted: #{e.message}"
    nil
  end

  def self.parse_erc20_fixed_denomination_token_transferred(log)
    # ERC20FixedDenominationTokenTransferred(bytes32 indexed deployEthscriptionId, address indexed from, address indexed to, uint256 amount, uint256 mintId, bytes32 ethscriptionId)
    deploy_tx_hash = log['topics'][1]
    from_address = '0x' + log['topics'][2][-40..] if log['topics'][2]  # Last 20 bytes
    to_address = '0x' + log['topics'][3][-40..] if log['topics'][3]

    data = [log['data'].delete_prefix('0x')].pack('H*')
    decoded = Eth::Abi.decode(['uint256', 'uint256', 'bytes32'], data)

    {
      event: 'ERC20FixedDenominationTokenTransferred',
      deploy_tx_hash: deploy_tx_hash,
      from: from_address,
      to: to_address,
      amount: decoded[0],
      mint_id: decoded[1],
      ethscription_tx_hash: '0x' + decoded[2].unpack1('H*')
    }
  rescue => e
    Rails.logger.error "Failed to parse ERC20FixedDenominationTokenTransferred: #{e.message}"
    nil
  end

  def self.parse_erc721_collection_deployed(log)
    # ERC721CollectionDeployed(bytes32 indexed deployEthscriptionId, address indexed collectionAddress, string tick)
    deploy_ethscription_id = log['topics'][1]
    collection_address = '0x' + log['topics'][2][-40..] if log['topics'][2]  # Last 20 bytes

    data = [log['data'].delete_prefix('0x')].pack('H*')
    decoded = Eth::Abi.decode(['string'], data)

    {
      event: 'ERC721CollectionDeployed',
      deploy_ethscription_id: deploy_ethscription_id,
      collection_address: collection_address,
      tick: decoded[0]
    }
  rescue => e
    Rails.logger.error "Failed to parse ERC721CollectionDeployed: #{e.message}"
    nil
  end

  def self.parse_collection_created(log)
    # CollectionCreated(bytes32 indexed collectionId, address indexed collectionContract, string name, string symbol, uint256 maxSize)
    collection_id = log['topics'][1]
    collection_contract = '0x' + log['topics'][2][-40..] if log['topics'][2]

    if log['data'] && log['data'] != '0x'
      data = [log['data'].delete_prefix('0x')].pack('H*')
      decoded = Eth::Abi.decode(['string', 'string', 'uint256'], data)

      {
        event: 'CollectionCreated',
        collection_id: collection_id,
        collection_contract: collection_contract,
        name: decoded[0],
        symbol: decoded[1],
        max_size: decoded[2]
      }
    else
      # Return partial result if data is missing
      {
        event: 'CollectionCreated',
        collection_id: collection_id,
        collection_contract: collection_contract,
        name: '',
        symbol: '',
        max_size: 0
      }
    end
  rescue => e
    Rails.logger.error "Failed to parse CollectionCreated: #{e.message}"
    # Return partial result so event is still recognized
    {
      event: 'CollectionCreated',
      collection_id: log['topics'][1],
      collection_contract: log['topics'][2] ? '0x' + log['topics'][2][-40..] : nil
    }
  end

  def self.parse_items_added(log)
    # ItemsAdded(bytes32 indexed collectionId, uint256 count, bytes32 updateTxHash)
    collection_id = log['topics'][1]

    data = [log['data'].delete_prefix('0x')].pack('H*')
    decoded = Eth::Abi.decode(['uint256', 'bytes32'], data)

    {
      event: 'ItemsAdded',
      collection_id: collection_id,
      count: decoded[0],
      update_tx_hash: '0x' + decoded[1].unpack1('H*')
    }
  rescue => e
    Rails.logger.error "Failed to parse ItemsAdded: #{e.message}"
    nil
  end

  def self.parse_items_removed(log)
    # ItemsRemoved(bytes32 indexed collectionId, uint256 count, bytes32 updateTxHash)
    collection_id = log['topics'][1]

    data = [log['data'].delete_prefix('0x')].pack('H*')
    decoded = Eth::Abi.decode(['uint256', 'bytes32'], data)

    {
      event: 'ItemsRemoved',
      collection_id: collection_id,
      count: decoded[0],
      update_tx_hash: '0x' + decoded[1].unpack1('H*')
    }
  rescue => e
    Rails.logger.error "Failed to parse ItemsRemoved: #{e.message}"
    nil
  end

  def self.parse_collection_edited(log)
    # CollectionEdited(bytes32 indexed collectionId)
    {
      event: 'CollectionEdited',
      collection_id: log['topics'][1]
    }
  end

  # Helper to check if a receipt contains a successful protocol execution
  def self.protocol_succeeded?(receipt)
    events = parse_receipt_events(receipt)
    events.any? { |e| e[:event] == 'ProtocolHandlerSuccess' }
  end

  # Helper to get protocol failure reason
  def self.get_protocol_failure_reason(receipt)
    events = parse_receipt_events(receipt)
    failed_event = events.find { |e| e[:event] == 'ProtocolHandlerFailed' }
    failed_event ? failed_event[:reason] : nil
  end
end
