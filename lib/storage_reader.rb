class StorageReader
  ETHSCRIPTIONS_ADDRESS = SysConfig::ETHSCRIPTIONS_ADDRESS.to_hex

  # Define the new denormalized Ethscription struct ABI
  ETHSCRIPTION_STRUCT_ABI = {
    'components' => [
      { 'name' => 'ethscriptionId', 'type' => 'bytes32' },
      { 'name' => 'ethscriptionNumber', 'type' => 'uint256' },
      { 'name' => 'contentUriHash', 'type' => 'bytes32' },
      { 'name' => 'contentSha', 'type' => 'bytes32' },
      { 'name' => 'mimetype', 'type' => 'string' },
      { 'name' => 'content', 'type' => 'bytes' },
      { 'name' => 'currentOwner', 'type' => 'address' },
      { 'name' => 'creator', 'type' => 'address' },
      { 'name' => 'initialOwner', 'type' => 'address' },
      { 'name' => 'previousOwner', 'type' => 'address' },
      { 'name' => 'l1BlockHash', 'type' => 'bytes32' },
      { 'name' => 'l1BlockNumber', 'type' => 'uint256' },
      { 'name' => 'l2BlockNumber', 'type' => 'uint256' },
      { 'name' => 'createdAt', 'type' => 'uint256' },
      { 'name' => 'esip6', 'type' => 'bool' }
    ],
    'type' => 'tuple'
  }

  # Define the old storage struct ABI for getEthscriptionWithoutContent
  ETHSCRIPTION_STORAGE_STRUCT_ABI = {
    'components' => [
      { 'name' => 'contentUriHash', 'type' => 'bytes32' },
      { 'name' => 'contentSha', 'type' => 'bytes32' },
      { 'name' => 'l1BlockHash', 'type' => 'bytes32' },
      { 'name' => 'creator', 'type' => 'address' },
      { 'name' => 'createdAt', 'type' => 'uint48' },
      { 'name' => 'l1BlockNumber', 'type' => 'uint48' },
      { 'name' => 'mimetype', 'type' => 'string' },
      { 'name' => 'initialOwner', 'type' => 'address' },
      { 'name' => 'ethscriptionNumber', 'type' => 'uint48' },
      { 'name' => 'esip6', 'type' => 'bool' },
      { 'name' => 'previousOwner', 'type' => 'address' },
      { 'name' => 'l2BlockNumber', 'type' => 'uint48' }
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
        { 'name' => 'ethscriptionId', 'type' => 'bytes32' }
      ],
      'outputs' => [
        ETHSCRIPTION_STRUCT_ABI
      ]
    },
    {
      'name' => 'getEthscription',
      'type' => 'function',
      'stateMutability' => 'view',
      'inputs' => [
        { 'name' => 'ethscriptionId', 'type' => 'bytes32' },
        { 'name' => 'includeContent', 'type' => 'bool' }
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
        { 'name' => 'ethscriptionId', 'type' => 'bytes32' }
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
        { 'name' => 'ethscriptionId', 'type' => 'bytes32' }
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
    }
  ]

  class << self
    def get_ethscription_with_content(tx_hash, block_tag: 'latest')
      # Use the new getEthscription function that returns everything including content
      tx_hash_bytes32 = format_bytes32(tx_hash)

      # Build function signature and encode parameters
      function_sig = Eth::Util.keccak256('getEthscription(bytes32)')[0...4]

      # Encode the parameter (bytes32 is already 32 bytes)
      calldata = function_sig + [tx_hash_bytes32].pack('H*')

      # Make the eth_call
      result = eth_call('0x' + calldata.unpack1('H*'), block_tag)
      # When contract returns 0x/0x0, the ethscription doesn't exist (not an error, just not found)
      return nil if result == '0x' || result == '0x0'

      # If result is nil, that's an RPC/network error
      raise StandardError, "RPC call failed for ethscription #{tx_hash}" if result.nil?

      # Decode the single Ethscription struct with all fields including content
      # New struct order: ethscriptionId, ethscriptionNumber, contentUriHash, contentSha, mimetype, content,
      #                   currentOwner, creator, initialOwner, previousOwner, l1BlockHash,
      #                   l1BlockNumber, l2BlockNumber, createdAt, esip6
      types = ['(bytes32,uint256,bytes32,bytes32,string,bytes,address,address,address,address,bytes32,uint256,uint256,uint256,bool)']
      decoded = Eth::Abi.decode(types, result)

      # The struct is returned as an array
      ethscription_data = decoded[0]

      {
        # Identity
        ethscription_id: '0x' + ethscription_data[0].unpack1('H*'),
        ethscription_number: ethscription_data[1],

        # Content fields
        content_uri_hash: '0x' + ethscription_data[2].unpack1('H*'),
        content_sha: '0x' + ethscription_data[3].unpack1('H*'),
        mimetype: ethscription_data[4],
        content: ethscription_data[5],  # content is now at index 5

        # Ownership fields
        current_owner: Eth::Address.new(ethscription_data[6]).to_s,
        creator: Eth::Address.new(ethscription_data[7]).to_s,
        initial_owner: Eth::Address.new(ethscription_data[8]).to_s,
        previous_owner: Eth::Address.new(ethscription_data[9]).to_s,

        # Block/time data
        l1_block_hash: '0x' + ethscription_data[10].unpack1('H*'),
        l1_block_number: ethscription_data[11],
        l2_block_number: ethscription_data[12],
        created_at: ethscription_data[13],

        # Protocol
        esip6: ethscription_data[14]
      }
    rescue => e
      Rails.logger.error "Failed to get ethscription with content #{tx_hash}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n") if Rails.env.development?
      raise e
    end

    def get_ethscription(tx_hash, block_tag: 'latest')
      # Use getEthscription with includeContent=false for gas-optimized queries without content
      tx_hash_bytes32 = format_bytes32(tx_hash)

      # Build function signature and encode parameters
      function_sig = Eth::Util.keccak256('getEthscription(bytes32,bool)')[0...4]

      # Encode the parameters: bytes32 and bool (false)
      # bytes32 (32 bytes) + bool padded to 32 bytes (0x00...00 for false)
      calldata = function_sig + [tx_hash_bytes32].pack('H*') + "\x00" * 32  # false as 32 bytes of zeros

      # Make the eth_call
      result = eth_call('0x' + calldata.unpack1('H*'), block_tag)
      # Deterministic not-found from contract returns 0x/0x0
      return nil if result == '0x' || result == '0x0'
      # Nil indicates an RPC/network failure
      raise StandardError, "RPC call failed for ethscription #{tx_hash}" if result.nil?

      # Decode the Ethscription struct without content
      # Struct order: ethscriptionId, ethscriptionNumber, contentUriHash, contentSha, mimetype, content (empty),
      #               currentOwner, creator, initialOwner, previousOwner, l1BlockHash,
      #               l1BlockNumber, l2BlockNumber, createdAt, esip6
      types = ['(bytes32,uint256,bytes32,bytes32,string,bytes,address,address,address,address,bytes32,uint256,uint256,uint256,bool)']
      decoded = Eth::Abi.decode(types, result)

      # The struct is returned as an array
      ethscription_data = decoded[0]

      {
        # Identity
        ethscription_id: '0x' + ethscription_data[0].unpack1('H*'),
        ethscription_number: ethscription_data[1],

        # Content fields (no actual content bytes)
        content_uri_hash: '0x' + ethscription_data[2].unpack1('H*'),
        content_sha: '0x' + ethscription_data[3].unpack1('H*'),
        mimetype: ethscription_data[4],
        # Skip content at index 5 (it's empty for WithoutContent)

        # Ownership fields
        current_owner: Eth::Address.new(ethscription_data[6]).to_s,
        creator: Eth::Address.new(ethscription_data[7]).to_s,
        initial_owner: Eth::Address.new(ethscription_data[8]).to_s,
        previous_owner: Eth::Address.new(ethscription_data[9]).to_s,

        # Block/time data
        l1_block_hash: '0x' + ethscription_data[10].unpack1('H*'),
        l1_block_number: ethscription_data[11],
        l2_block_number: ethscription_data[12],
        created_at: ethscription_data[13],

        # Protocol
        esip6: ethscription_data[14]
      }
    rescue EthRpcClient::ExecutionRevertedError => e
      # Contract reverted - ethscription doesn't exist
      Rails.logger.debug "Ethscription #{tx_hash} doesn't exist (contract reverted): #{e.message}"
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
    rescue EthRpcClient::ExecutionRevertedError => e
      # Contract reverted - ethscription doesn't exist
      Rails.logger.debug "Ethscription content #{tx_hash} doesn't exist (contract reverted): #{e.message}"
      nil
    end

    def get_owner(ethscription_id, block_tag: 'latest')
      # Build function signature
      function_sig = Eth::Util.keccak256('ownerOf(bytes32)')[0...4]

      # Parameter is the ethscription ID (bytes32)
      ethscription_id_bytes32 = format_bytes32(ethscription_id)

      # Encode the parameter
      calldata = function_sig + [ethscription_id_bytes32].pack('H*')

      # Make the eth_call
      result = eth_call('0x' + calldata.unpack1('H*'), block_tag)
      # Some nodes return 0x when the call yields no data
      return nil if result == '0x'
      # Nil indicates an RPC/network failure
      raise StandardError, "RPC call failed for ownerOf #{ethscription_id}" if result.nil?

      # Decode the result - ownerOf returns a single address
      decoded = Eth::Abi.decode(['address'], result)
      Eth::Address.new(decoded[0]).to_s
    rescue EthRpcClient::ExecutionRevertedError => e
      # Contract reverted - token doesn't exist
      Rails.logger.debug "Ethscription #{ethscription_id} doesn't exist (contract reverted): #{e.message}"
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
