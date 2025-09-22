# Module to handle EVM-based ethscription processing
# Replaces direct database writes with contract calls
module EvmEthscriptionProcessor
  extend ActiveSupport::Concern
  
  # Create ethscription from input via EVM
  def create_ethscription_from_input!
    # Protocol signal detection - both conditions must be met for a valid creation attempt:
    # 1. Valid data URI format (user is using the protocol)
    # 2. Has a recipient (required for ethscription creation)
    return unless DataUri.valid?(utf8_input) && to_address.present?
    
    # Check if this is a token operation
    token_op = detect_token_operation(utf8_input)
    
    # Build parameters - just translate what the user provided
    params = if token_op
      EthscriptionsParamMapper.build_create_params_from_input(self, token_op)
    else
      EthscriptionsParamMapper.build_create_params_from_input(self)
    end
    
    # Skip if params are malformed (shouldn't happen with valid data URI)
    return unless EthscriptionsParamMapper.params_well_formed?(params, :createEthscription)
    
    # Send to contract
    send_to_ethscriptions_contract(:createEthscription, params, from_address: from_address)
  end
  
  # Create ethscription from events via EVM
  def create_ethscription_from_events!
    ethscription_creation_events.each do |creation_event|
      next if creation_event['topics'].length != 2
    
      begin
        initial_owner = Eth::Abi.decode(['address'], creation_event['topics'].second).first
        content_uri_data = Eth::Abi.decode(['string'], creation_event['data']).first
        content_uri = HexDataProcessor.clean_utf8(content_uri_data)
      rescue Eth::Abi::DecodingError
        # Can't decode the event - skip it
        next
      end
      
      # Build parameters - just translate what's in the event
      params = EthscriptionsParamMapper.build_create_params(
        self,
        creator: creation_event['address'],
        initial_owner: initial_owner,
        content_uri: content_uri
      )
      
      # Skip if params are malformed
      next unless EthscriptionsParamMapper.params_well_formed?(params, :createEthscription)
      
      # Send to contract
      send_to_ethscriptions_contract(:createEthscription, params, from_address: creation_event['address'])
    end
  end
  
  # Create transfers from input via EVM
  def create_ethscription_transfers_from_input!
    return unless transfers_ethscription_via_input?
    
    concatenated_hashes = input_no_prefix.scan(/.{64}/).map { |hash| "0x#{hash}" }
    
    # Process each transfer individually to allow partial success
    # (some transfers may fail while others succeed)
    concatenated_hashes.each do |ethscription_tx_hash|
      params = EthscriptionsParamMapper.build_transfer_params(
        ethscription_tx_hash: ethscription_tx_hash,
        to_address: to_address
      )
      
      # Skip if params are malformed
      next unless EthscriptionsParamMapper.params_well_formed?(params, :transferEthscription)
      
      # Send individual transfer to contract
      send_to_ethscriptions_contract(:transferEthscription, params, from_address: from_address)
    end
  end
  
  # Create transfers from events via EVM
  def create_ethscription_transfers_from_events!
    ethscription_transfer_events.each do |log|
      topics = log['topics']
      event_type = topics.first
      
      ethscription_tx_hash = nil
      to_address = nil
      from_address = log['address']
      
      if event_type == Esip1EventSig
        next if topics.length != 3
        
        begin
          to_address = Eth::Abi.decode(['address'], topics.second).first
          ethscription_tx_hash = Eth::Util.bin_to_prefixed_hex(
            Eth::Abi.decode(['bytes32'], topics.third).first
          )
        rescue Eth::Abi::DecodingError
          next
        end
      elsif event_type == Esip2EventSig
        next if topics.length != 4
        
        begin
          event_previous_owner = Eth::Abi.decode(['address'], topics.second).first
          to_address = Eth::Abi.decode(['address'], topics.third).first
          ethscription_tx_hash = Eth::Util.bin_to_prefixed_hex(
            Eth::Abi.decode(['bytes32'], topics.fourth).first
          )
        rescue Eth::Abi::DecodingError
          next
        end
        
        # ESIP-2: Transfer for previous owner - use different contract method
        params = EthscriptionsParamMapper.build_transfer_for_previous_owner_params(
          ethscription_tx_hash: ethscription_tx_hash,
          to_address: to_address,
          previous_owner: event_previous_owner
        )
        
        # Skip if params are malformed
        next unless EthscriptionsParamMapper.params_well_formed?(params, :transferEthscriptionForPreviousOwner)
        
        # Send to contract
        send_to_ethscriptions_contract(:transferEthscriptionForPreviousOwner, params, from_address: from_address)
        next
      end
      
      next unless ethscription_tx_hash && to_address
      
      # ESIP-1: Regular transfer
      params = EthscriptionsParamMapper.build_transfer_params(
        ethscription_tx_hash: ethscription_tx_hash,
        to_address: to_address
      )
      
      # Skip if params are malformed
      next unless EthscriptionsParamMapper.params_well_formed?(params, :transferEthscription)
      
      # Send to contract
      send_to_ethscriptions_contract(:transferEthscription, params, from_address: from_address)
    end
  end
  
  private
  
  # Detect if this is a token operation (deploy or mint)
  def detect_token_operation(content_uri)
    return nil unless content_uri.start_with?('data:,')
    
    begin
      json_str = content_uri.sub('data:,', '')
      json = JSON.parse(json_str)
      
      # Check if it's a token operation
      return nil unless json['p'].present? && (json['op'] == 'deploy' || json['op'] == 'mint')
      
      {
        protocol: json['p'],
        operation: json['op'],
        tick: json['tick'],
        max: json['max']&.to_i,
        lim: json['lim']&.to_i,
        id: json['id']&.to_i,
        amt: json['amt']&.to_i
      }
    rescue JSON::ParserError
      nil
    end
  end
  
  # Simplified contract call - in production this would use the engine API
  def send_to_ethscriptions_contract(method, params, from_address:)
    Rails.logger.info({
      event: "evm_call",
      method: method,
      params: params,
      from_address: from_address,
      block_number: block_number,
      transaction_hash: transaction_hash
    }.to_json)
  end
end
