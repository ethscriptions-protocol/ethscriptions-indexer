class StorageReader
  ETHSCRIPTIONS_ADDRESS = '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE'

  # Define the nested ContentInfo struct
  CONTENT_INFO_STRUCT = {
    'components' => [
      { 'name' => 'contentUriHash', 'type' => 'bytes32' },
      { 'name' => 'contentSha', 'type' => 'bytes32' },
      { 'name' => 'mimetype', 'type' => 'string' },
      { 'name' => 'mediaType', 'type' => 'string' },
      { 'name' => 'mimeSubtype', 'type' => 'string' },
      { 'name' => 'esip6', 'type' => 'bool' }
    ],
    'type' => 'tuple'
  }

  # Define the Ethscription struct ABI with nested ContentInfo
  ETHSCRIPTION_STRUCT_ABI = {
    'components' => [
      CONTENT_INFO_STRUCT,  # ContentInfo content
      { 'name' => 'creator', 'type' => 'address' },
      { 'name' => 'initialOwner', 'type' => 'address' },
      { 'name' => 'previousOwner', 'type' => 'address' },
      { 'name' => 'ethscriptionNumber', 'type' => 'uint256' },
      { 'name' => 'createdAt', 'type' => 'uint256' },
      { 'name' => 'l1BlockNumber', 'type' => 'uint64' },
      { 'name' => 'l2BlockNumber', 'type' => 'uint64' },
      { 'name' => 'l1BlockHash', 'type' => 'bytes32' }
    ],
    'type' => 'tuple'
  }

  # Contract ABI - only the functions we need
  CONTRACT_ABI = [
    {
      'name' => 'getEthscription',
      'type' => 'function',
      'stateMutability' => 'view',
      'inputs' => [
        { 'name' => 'transactionHash', 'type' => 'bytes32' }
      ],
      'outputs' => [
        ETHSCRIPTION_STRUCT_ABI
      ]
    },
    {
      'name' => 'getEthscriptionContent',
      'type' => 'function',
      'stateMutability' => 'view',
      'inputs' => [
        { 'name' => 'transactionHash', 'type' => 'bytes32' }
      ],
      'outputs' => [
        { 'name' => '', 'type' => 'bytes' }
      ]
    },
    {
      'name' => 'ownerOf',
      'type' => 'function',
      'stateMutability' => 'view',
      'inputs' => [
        { 'name' => 'transactionHash', 'type' => 'bytes32' }
      ],
      'outputs' => [
        { 'name' => '', 'type' => 'address' }
      ]
    },
    {
      'name' => 'totalSupply',
      'type' => 'function',
      'stateMutability' => 'view',
      'inputs' => [],
      'outputs' => [
        { 'name' => '', 'type' => 'uint256' }
      ]
    },
    {
      'name' => 'getEthscriptionWithContent',
      'type' => 'function',
      'stateMutability' => 'view',
      'inputs' => [
        { 'name' => 'txHash', 'type' => 'bytes32' }
      ],
      'outputs' => [
        { 'name' => 'ethscription', **ETHSCRIPTION_STRUCT_ABI },
        { 'name' => 'content', 'type' => 'bytes' }
      ]
    }
  ]

  class << self
    def get_ethscription_with_content(tx_hash, block_tag: 'latest')
      # Single call to get both ethscription and content
      tx_hash_bytes32 = format_bytes32(tx_hash)

      # Build function signature and encode parameters
      function_sig = Eth::Util.keccak256('getEthscriptionWithContent(bytes32)')[0...4]

      # Encode the parameter (bytes32 is already 32 bytes)
      calldata = function_sig + [tx_hash_bytes32].pack('H*')

      # Make the eth_call
      result = eth_call('0x' + calldata.unpack1('H*'), block_tag)
      raise StandardError, "Ethscription not found: #{tx_hash}" if result.nil? || result == '0x' || result == '0x0'

      # Decode the tuple: (Ethscription, bytes)
      types = ['((bytes32,bytes32,string,string,string,bool),address,address,address,uint256,uint256,uint64,uint64,bytes32)', 'bytes']
      decoded = Eth::Abi.decode(types, result)

      # Extract ethscription struct and content
      ethscription_data = decoded[0]
      content_data = decoded[1]
      content_info = ethscription_data[0]  # Nested ContentInfo struct

      {
        # ContentInfo fields
        content_uri_hash: '0x' + content_info[0].unpack1('H*'),
        content_sha: '0x' + content_info[1].unpack1('H*'),
        mimetype: content_info[2],
        media_type: content_info[3],
        mime_subtype: content_info[4],
        esip6: content_info[5],

        # Main Ethscription fields
        creator: Eth::Address.new(ethscription_data[1]).to_s,
        initial_owner: Eth::Address.new(ethscription_data[2]).to_s,
        previous_owner: Eth::Address.new(ethscription_data[3]).to_s,
        ethscription_number: ethscription_data[4],
        created_at: ethscription_data[5],
        l1_block_number: ethscription_data[6],
        l2_block_number: ethscription_data[7],
        l1_block_hash: '0x' + ethscription_data[8].unpack1('H*'),

        # Content
        content: content_data
      }
    rescue => e
      Rails.logger.error "Failed to get ethscription with content #{tx_hash}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n") if Rails.env.development?
      raise e
    end

    def get_ethscription(tx_hash, block_tag: 'latest')
      # Ensure tx_hash is properly formatted as bytes32
      tx_hash_bytes32 = format_bytes32(tx_hash)

      # Build function signature and encode parameters
      function_sig = Eth::Util.keccak256('getEthscription(bytes32)')[0...4]

      # Encode the parameter (bytes32 is already 32 bytes)
      calldata = function_sig + [tx_hash_bytes32].pack('H*')

      # Make the eth_call
      result = eth_call('0x' + calldata.unpack1('H*'), block_tag)
      return nil if result.nil? || result == '0x' || result == '0x0'

      # Decode using Eth::Abi
      # Updated types for nested struct: ContentInfo is a tuple within the main tuple
      types = ['((bytes32,bytes32,string,string,string,bool),address,address,address,uint256,uint256,uint64,uint64,bytes32)']
      decoded = Eth::Abi.decode(types, result)

      # The struct is returned as an array within an array
      ethscription_data = decoded[0]
      content_info = ethscription_data[0]  # Nested ContentInfo struct

      {
        # ContentInfo fields
        content_uri_hash: '0x' + content_info[0].unpack1('H*'),
        content_sha: '0x' + content_info[1].unpack1('H*'),
        mimetype: content_info[2],
        media_type: content_info[3],
        mime_subtype: content_info[4],
        esip6: content_info[5],

        # Main Ethscription fields
        creator: Eth::Address.new(ethscription_data[1]).to_s,
        initial_owner: Eth::Address.new(ethscription_data[2]).to_s,
        previous_owner: Eth::Address.new(ethscription_data[3]).to_s,
        ethscription_number: ethscription_data[4],
        created_at: ethscription_data[5],
        l1_block_number: ethscription_data[6],
        l2_block_number: ethscription_data[7],
        l1_block_hash: '0x' + ethscription_data[8].unpack1('H*')
      }
    rescue => e
      Rails.logger.error "Failed to get ethscription #{tx_hash}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n") if Rails.env.development?
      nil
    end

    def get_ethscription_content(tx_hash, block_tag: 'latest')
      # Ensure tx_hash is properly formatted as bytes32
      tx_hash_bytes32 = format_bytes32(tx_hash)

      # Build function signature and encode parameters
      function_sig = Eth::Util.keccak256('getEthscriptionContent(bytes32)')[0...4]

      # Encode the parameter (bytes32 is already 32 bytes)
      calldata = function_sig + [tx_hash_bytes32].pack('H*')

      # Make the eth_call
      result = eth_call('0x' + calldata.unpack1('H*'), block_tag)
      return nil if result.nil? || result == '0x' || result == '0x0'

      # Decode using Eth::Abi - returns bytes
      decoded = Eth::Abi.decode(['bytes'], result)

      # Return the raw bytes content
      decoded[0]
    rescue => e
      Rails.logger.error "Failed to get ethscription content #{tx_hash}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n") if Rails.env.development?
      binding.irb if ENV['DEBUG'] == '1'
      raise e
    end

    def get_owner(token_id, block_tag: 'latest')
      # Build function signature
      function_sig = Eth::Util.keccak256('ownerOf(bytes32)')[0...4]

      # Token ID is the transaction hash as uint256
      token_id_bytes32 = format_bytes32(token_id)

      # Encode the parameter
      calldata = function_sig + [token_id_bytes32].pack('H*')

      # Make the eth_call
      result = eth_call('0x' + calldata.unpack1('H*'), block_tag)
      return nil if result.nil? || result == '0x'

      # Decode the result - ownerOf returns a single address
      decoded = Eth::Abi.decode(['address'], result)
      Eth::Address.new(decoded[0]).to_s
    rescue => e
      Rails.logger.error "Failed to get owner of #{token_id}: #{e.message}"
      nil
    end

    def get_total_supply(block_tag: 'latest')
      # Build function signature
      function_sig = Eth::Util.keccak256('totalSupply()')[0...4]

      # No parameters for totalSupply
      calldata = '0x' + function_sig.unpack1('H*')

      # Make the eth_call
      result = eth_call(calldata, block_tag)
      return 0 if result.nil? || result == '0x'

      # Decode the result
      decoded = Eth::Abi.decode(['uint256'], result)
      decoded[0]
    rescue => e
      Rails.logger.error "Failed to get total supply: #{e.message}"
      0
    end

    private

    def eth_call(calldata, block_tag = 'latest')
      # calldata should be a hex string starting with 0x
      EthRpcClient.l2.call('eth_call', [{
        to: ETHSCRIPTIONS_ADDRESS,
        data: calldata
      }, block_tag])
    end

    def format_bytes32(hex_value)
      # Remove 0x prefix if present and ensure it's 32 bytes
      clean_hex = hex_value.to_s.delete_prefix('0x')

      # Pad or truncate to 32 bytes
      if clean_hex.length > 64
        clean_hex[0...64]
      else
        clean_hex.rjust(64, '0')
      end
    end

    def format_uint256(hex_value)
      # Convert hex to integer (transaction hash as uint256)
      clean_hex = hex_value.to_s.delete_prefix('0x')
      clean_hex.to_i(16)
    end
  end
end
