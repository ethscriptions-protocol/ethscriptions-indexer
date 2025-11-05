class CollectionsReader
  COLLECTIONS_MANAGER_ADDRESS = '0x3300000000000000000000000000000000000006'
  ZERO_ADDRESS = '0x0000000000000000000000000000000000000000'

  # Define struct ABIs matching CollectionsManager.sol
  # Contract ABI for functions we need
  CONTRACT_ABI = [
    {
      'name' => 'getCollection',
      'type' => 'function',
      'stateMutability' => 'view',
      'inputs' => [
        { 'name' => 'collectionId', 'type' => 'bytes32' }
      ],
      'outputs' => [
        [
          { 'name' => 'collectionContract', 'type' => 'address' },
          { 'name' => 'locked', 'type' => 'bool' },
          { 'name' => 'name', 'type' => 'string' },
          { 'name' => 'symbol', 'type' => 'string' },
          { 'name' => 'maxSupply', 'type' => 'uint256' },
          { 'name' => 'description', 'type' => 'string' },
          { 'name' => 'logoImageUri', 'type' => 'string' },
          { 'name' => 'bannerImageUri', 'type' => 'string' },
          { 'name' => 'backgroundColor', 'type' => 'string' },
          { 'name' => 'websiteLink', 'type' => 'string' },
          { 'name' => 'twitterLink', 'type' => 'string' },
          { 'name' => 'discordLink', 'type' => 'string' },
          { 'name' => 'merkleRoot', 'type' => 'bytes32' }
        ]
      ]
    }
  ]

  def self.get_collection_state(collection_id, block_tag: 'latest')
    # Encode the function call
    input_types = ['bytes32']

    # Encode parameters
    encoded_params = Eth::Abi.encode(input_types, [normalize_bytes32(collection_id)])
    # Use the actual function name from the contract
    data = fetch_collection(collection_id, block_tag)
    return nil if data.nil?
    collection_contract = data[:collectionContract]
    locked = data[:locked]
    current_size = 0
    if collection_contract && collection_contract != ZERO_ADDRESS
      current_size = get_collection_supply(collection_contract, block_tag: block_tag)
    end

    {
      collectionContract: collection_contract,
      createTxHash: format_bytes32_hex(collection_id),
      currentSize: current_size,
      locked: locked
    }
  end

  def self.get_collection_metadata(collection_id, block_tag: 'latest')
    data = fetch_collection(collection_id, block_tag)
    return nil if data.nil?

    {
      name: data[:name],
      symbol: data[:symbol],
      maxSupply: data[:maxSupply],
      totalSupply: data[:maxSupply],
      description: data[:description],
      logoImageUri: data[:logoImageUri],
      bannerImageUri: data[:bannerImageUri],
      backgroundColor: data[:backgroundColor],
      websiteLink: data[:websiteLink],
      twitterLink: data[:twitterLink],
      discordLink: data[:discordLink],
      merkleRoot: data[:merkleRoot]
    }
  end

  def self.fetch_collection(collection_id, block_tag)
    input_types = ['bytes32']
    encoded_params = Eth::Abi.encode(input_types, [normalize_bytes32(collection_id)])
    function_selector = Eth::Util.keccak256('getCollection(bytes32)')[0..3]
    data = (function_selector + encoded_params).unpack1('H*')
    data = '0x' + data

    # Make the call
    result = EthRpcClient.l2.eth_call(
      to: COLLECTIONS_MANAGER_ADDRESS,
      data: data,
      block_number: block_tag
    )

    return nil if result == '0x' || result.nil?

    output_types = ['(address,bool,string,string,uint256,string,string,string,string,string,string,string,bytes32)']
    decoded = Eth::Abi.decode(output_types, [result.delete_prefix('0x')].pack('H*'))
    tuple = decoded[0]

    {
      collectionContract: tuple[0],
      locked: tuple[1],
      name: tuple[2],
      symbol: tuple[3],
      maxSupply: tuple[4],
      description: tuple[5],
      logoImageUri: tuple[6],
      bannerImageUri: tuple[7],
      backgroundColor: tuple[8],
      websiteLink: tuple[9],
      twitterLink: tuple[10],
      discordLink: tuple[11],
      merkleRoot: '0x' + tuple[12].unpack1('H*')
    }
  end

  def self.collection_exists?(collection_id, block_tag: 'latest')
    state = get_collection_state(collection_id, block_tag: block_tag)
    return false if state.nil?

    # Collection exists if collectionContract is not zero address
    state[:collectionContract] != '0x0000000000000000000000000000000000000000'
  end

  def self.get_collection_item(collection_id, item_index, block_tag: 'latest')
    # Encode function call for getCollectionItem(bytes32,uint256)
    input_types = ['bytes32', 'uint256']
    encoded_params = Eth::Abi.encode(input_types, [normalize_bytes32(collection_id), item_index])
    function_selector = Eth::Util.keccak256('getCollectionItem(bytes32,uint256)')[0..3]
    data = (function_selector + encoded_params).unpack1('H*')
    data = '0x' + data

    # Make the call
    result = EthRpcClient.l2.eth_call(
      to: COLLECTIONS_MANAGER_ADDRESS,
      data: data,
      block_number: block_tag
    )

    return nil if result == '0x' || result.nil?

    # Decode the ItemData struct
    # ItemData: (uint256,string,bytes32,string,string,Attribute[])
    output_types = ['(uint256,string,bytes32,string,string,(string,string)[])']
    decoded = Eth::Abi.decode(output_types, [result.delete_prefix('0x')].pack('H*'))
    item_tuple = decoded[0]

    {
      itemIndex: item_tuple[0],
      name: item_tuple[1],
      ethscriptionId: '0x' + item_tuple[2].unpack1('H*'),
      backgroundColor: item_tuple[3],
      description: item_tuple[4],
      attributes: item_tuple[5] # Array of [trait_type, value] tuples
    }
  rescue => e
    Rails.logger.error "Failed to get item #{item_index} from collection #{collection_id}: #{e.message}"
    nil
  end

  def self.get_collection_owner(collection_id, block_tag: 'latest')
    # Get collection state first to get the contract address
    state = get_collection_state(collection_id, block_tag: block_tag)
    return nil if state.nil? || state[:collectionContract] == '0x0000000000000000000000000000000000000000'

    # Call owner() on the collection contract
    function_selector = Eth::Util.keccak256('owner()')[0..3]
    data = '0x' + function_selector.unpack1('H*')

    # Make the call to the collection contract
    result = EthRpcClient.l2.eth_call(
      to: state[:collectionContract],
      data: data,
      block_number: block_tag
    )

    return nil if result == '0x' || result.nil?

    # Decode the owner address
    decoded = Eth::Abi.decode(['address'], [result.delete_prefix('0x')].pack('H*'))
    decoded[0]
  rescue => e
    Rails.logger.error "Failed to get owner for collection #{collection_id}: #{e.message}"
    nil
  end

  private

  def self.normalize_bytes32(value)
    # Ensure value is a 32-byte hex string
    hex = value.to_s.delete_prefix('0x')
    hex = hex.rjust(64, '0') if hex.length < 64
    [hex].pack('H*')
  end

  def self.format_bytes32_hex(value)
    hex = value.to_s.delete_prefix('0x')
    hex = hex.rjust(64, '0')[0,64]
    '0x' + hex.downcase
  end

  def self.get_collection_supply(collection_contract, block_tag: 'latest')
    function_selector = Eth::Util.keccak256('totalSupply()')[0..3]
    data = '0x' + function_selector.unpack1('H*')

    result = EthRpcClient.l2.eth_call(
      to: collection_contract,
      data: data,
      block_number: block_tag
    )

    return 0 if result == '0x' || result.nil?

    decoded = Eth::Abi.decode(['uint256'], [result.delete_prefix('0x')].pack('H*'))
    decoded[0]
  rescue => e
    Rails.logger.error "Failed to get supply for collection #{collection_contract}: #{e.message}"
    0
  end
end
