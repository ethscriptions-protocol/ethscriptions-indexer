# Strict extractor for the ERC-721 Ethscriptions collection protocol with canonical JSON validation
class Erc721EthscriptionsCollectionParser
  # Default return for invalid input
  DEFAULT_PARAMS = [''.b, ''.b, ''.b].freeze

  # Maximum value for uint256
  UINT256_MAX = 2**256 - 1

  # Operation schemas defining exact structure and ABI encoding
  OPERATION_SCHEMAS = {
    'create_collection' => {
      keys: %w[name symbol max_supply description logo_image_uri banner_image_uri background_color website_link twitter_link discord_link],
      # Contract expects an extra bytes32 merkleRoot at the end. We append zero when omitted.
      abi_type: '(string,string,uint256,string,string,string,string,string,string,string,bytes32)',
      validators: {
        'name' => :string,
        'symbol' => :string,
        'max_supply' => :uint256,
        'description' => :string,
        'logo_image_uri' => :string,
        'banner_image_uri' => :string,
        'background_color' => :string,
        'website_link' => :string,
        'twitter_link' => :string,
        'discord_link' => :string
      }
    },
    'create_and_add_self' => {
      keys: %w[metadata item],
      # ((CollectionParams),(ItemData)) with ItemData including bytes32[] merkle_proof
      abi_type: '((string,string,uint256,string,string,string,string,string,string,string,bytes32),(uint256,string,bytes32,string,string,(string,string)[],bytes32[]))',
      validators: {
        'metadata' => :collection_metadata,
        'item' => :single_item
      }
    },
    'add_items_batch' => {
      keys: %w[collection_id items],
      # Includes per-item merkle_proof (bytes32[]) as the final tuple element
      abi_type: '(bytes32,(uint256,string,bytes32,string,string,(string,string)[],bytes32[])[])',
      validators: {
        'collection_id' => :bytes32,
        'items' => :items_array
      }
    },
    'remove_items' => {
      keys: %w[collection_id ethscription_ids],
      abi_type: '(bytes32,bytes32[])',
      validators: {
        'collection_id' => :bytes32,
        'ethscription_ids' => :bytes32_array
      }
    },
    'edit_collection' => {
      keys: %w[collection_id description logo_image_uri banner_image_uri background_color website_link twitter_link discord_link],
      # Contract includes a bytes32 merkleRoot; append zero when omitted
      abi_type: '(bytes32,string,string,string,string,string,string,string,bytes32)',
      validators: {
        'collection_id' => :bytes32,
        'description' => :string,
        'logo_image_uri' => :string,
        'banner_image_uri' => :string,
        'background_color' => :string,
        'website_link' => :string,
        'twitter_link' => :string,
        'discord_link' => :string
      }
    },
    'edit_collection_item' => {
      keys: %w[collection_id item_index name background_color description attributes],
      abi_type: '(bytes32,uint256,string,string,string,(string,string)[])',
      validators: {
        'collection_id' => :bytes32,
        'item_index' => :uint256,
        'name' => :string,
        'background_color' => :string,
        'description' => :string,
        'attributes' => :attributes_array
      }
    },
    'lock_collection' => {
      keys: %w[collection_id],
      abi_type: 'bytes32', # Not a tuple
      validators: {
        'collection_id' => :bytes32
      }
    },
    'sync_ownership' => {
      keys: %w[collection_id ethscription_ids],
      abi_type: '(bytes32,bytes32[])',
      validators: {
        'collection_id' => :bytes32,
        'ethscription_ids' => :bytes32_array
      }
    }
  }.freeze

  # Item keys for add_items_batch validation
  ITEM_KEYS_MIN = %w[item_index name ethscription_id background_color description attributes].freeze
  ITEM_KEYS_WITH_PROOF = %w[item_index name ethscription_id background_color description attributes merkle_proof].freeze

  # Attribute keys for NFT metadata
  ATTRIBUTE_KEYS = %w[trait_type value].freeze

  class ValidationError < StandardError; end

  def self.extract(content_uri)
    new.extract(content_uri)
  end

  def extract(content_uri)
    return DEFAULT_PARAMS unless valid_data_uri?(content_uri)

    begin
      # Parse JSON (preserves key order)
      # Use DataUri to correctly handle optional parameters like ESIP6
      json_str = if content_uri.start_with?("data:,{")
        content_uri.sub(/\Adata:,/, '')
      else
        DataUri.new(content_uri).decoded_data
      end
      
      # TODO: make sure this is safe
      data = JSON.parse(json_str)

      # Must be an object
      return DEFAULT_PARAMS unless data.is_a?(Hash)

      # Check protocol
      return DEFAULT_PARAMS unless data['p'] == 'erc-721-ethscriptions-collection'

      # Get operation
      operation = data['op']
      return DEFAULT_PARAMS unless OPERATION_SCHEMAS.key?(operation)

      # Validate exact key order (including p and op at start)
      schema = OPERATION_SCHEMAS[operation]
      expected_keys = ['p', 'op'] + schema[:keys]
      return DEFAULT_PARAMS unless data.keys == expected_keys

      # Remove protocol fields for encoding
      encoding_data = data.reject { |k, _| k == 'p' || k == 'op' }

      # Validate field types and encode
      encoded_data = encode_operation(operation, encoding_data, schema)

      ['erc-721-ethscriptions-collection'.b, operation.b, encoded_data.b]

    rescue JSON::ParserError, ValidationError => e
      Rails.logger.debug "Collections extraction failed: #{e.message}" if defined?(Rails)
      DEFAULT_PARAMS
    end
  end

  private

  def valid_data_uri?(uri)
    DataUri.valid?(uri)
  end

  def encode_operation(operation, data, schema)
    # Validate and transform fields according to schema
    validated_data = validate_fields(data, schema[:validators])

    # Build values array based on operation
    values = case operation
    when 'create_collection'
      build_create_collection_values(validated_data)
    when 'create_and_add_self'
      build_create_and_add_self_values(validated_data)
    when 'add_items_batch'
      build_add_items_batch_values(validated_data)
    when 'remove_items'
      build_remove_items_values(validated_data)
    when 'edit_collection'
      build_edit_collection_values(validated_data)
    when 'edit_collection_item'
      build_edit_collection_item_values(validated_data)
    when 'lock_collection'
      build_lock_collection_values(validated_data)
    when 'sync_ownership'
      build_sync_ownership_values(validated_data)
    else
      raise ValidationError, "Unknown operation: #{operation}"
    end

    # Use ABI type from schema for encoding
    Eth::Abi.encode([schema[:abi_type]], [values])
  end

  def validate_fields(data, validators)
    validated = {}

    data.each do |key, value|
      validator = validators[key]

      # All fields must have explicit validators - no silent coercion
      unless validator
        raise ValidationError, "No validator defined for field: #{key}"
      end

      validated[key] = send("validate_#{validator}", value, key)
    end

    validated
  end

  # Validators

  def validate_string(value, field_name)
    unless value.is_a?(String)
      raise ValidationError, "Field #{field_name} must be a string, got #{value.class.name}"
    end
    value
  end

  def validate_uint256(value, field_name)
    unless value.is_a?(String) && value.match?(/\A(0|[1-9]\d*)\z/)
      raise ValidationError, "Invalid uint256 for #{field_name}: #{value}"
    end

    num = value.to_i
    if num > UINT256_MAX
      raise ValidationError, "Value exceeds uint256 maximum for #{field_name}: #{value}"
    end

    num
  end

  def validate_bytes32(value, field_name)
    unless value.is_a?(String) && value.match?(/\A0x[0-9a-f]{64}\z/)
      raise ValidationError, "Invalid bytes32 for #{field_name}: #{value}"
    end
    # Return as packed bytes for ABI encoding
    [value[2..]].pack('H*')
  end

  def validate_bytes32_array(value, field_name)
    unless value.is_a?(Array)
      raise ValidationError, "Expected array for #{field_name}"
    end

    value.map do |item|
      unless item.is_a?(String) && item.match?(/\A0x[0-9a-f]{64}\z/)
        raise ValidationError, "Invalid bytes32 in array: #{item}"
      end
      [item[2..]].pack('H*')
    end
  end

  def validate_items_array(value, field_name)
    unless value.is_a?(Array)
      raise ValidationError, "Expected array for #{field_name}"
    end

    value.map do |item|
      validate_item(item)
    end
  end

  def validate_single_item(value, field_name)
    unless value.is_a?(Hash)
      raise ValidationError, "Expected object for #{field_name}"
    end
    validate_item(value)
  end

  def validate_collection_metadata(value, field_name)
    unless value.is_a?(Hash)
      raise ValidationError, "Expected object for #{field_name}"
    end
    # Expected keys for metadata (merkle_root optional)
    expected_min_keys = %w[name symbol max_supply description logo_image_uri banner_image_uri background_color website_link twitter_link discord_link]
    unless value.keys == expected_min_keys || value.keys == (expected_min_keys + ['merkle_root'])
      raise ValidationError, "Invalid metadata keys or order"
    end

    {
      name: validate_string(value['name'], 'name'),
      symbol: validate_string(value['symbol'], 'symbol'),
      maxSupply: validate_uint256(value['max_supply'], 'max_supply'),
      description: validate_string(value['description'], 'description'),
      logoImageUri: validate_string(value['logo_image_uri'], 'logo_image_uri'),
      bannerImageUri: validate_string(value['banner_image_uri'], 'banner_image_uri'),
      backgroundColor: validate_string(value['background_color'], 'background_color'),
      websiteLink: validate_string(value['website_link'], 'website_link'),
      twitterLink: validate_string(value['twitter_link'], 'twitter_link'),
      discordLink: validate_string(value['discord_link'], 'discord_link'),
      merkleRoot: value.key?('merkle_root') ? validate_bytes32(value['merkle_root'], 'merkle_root') : nil
    }
  end

  def validate_item(item)
    unless item.is_a?(Hash)
      raise ValidationError, "Item must be an object"
    end

    # Check exact key order; allow optional merkle_proof
    has_proof =
      if item.keys == ITEM_KEYS_WITH_PROOF
        true
      elsif item.keys == ITEM_KEYS_MIN
        false
      else
        expected = "[#{ITEM_KEYS_MIN.join(', ')}] or [#{ITEM_KEYS_WITH_PROOF.join(', ')}]"
        raise ValidationError, "Invalid item keys or order. Expected: #{expected}, got: [#{item.keys.join(', ')}]"
      end

    # Validate each field - return in internal format for encoding
    result = {
      itemIndex: validate_uint256(item['item_index'], 'item_index'),
      name: validate_string(item['name'], 'name'),
      ethscriptionId: validate_bytes32(item['ethscription_id'], 'ethscription_id'),
      backgroundColor: validate_string(item['background_color'], 'background_color'),
      description: validate_string(item['description'], 'description'),
      attributes: validate_attributes_array(item['attributes'], 'attributes')
    }

    # Optional merkle proof; always include as bytes32[] (empty when omitted)
    result[:merkleProof] = has_proof ? validate_bytes32_array(item['merkle_proof'], 'merkle_proof') : []

    result
  end

  def validate_attributes_array(value, field_name)
    unless value.is_a?(Array)
      raise ValidationError, "Expected array for #{field_name}"
    end

    value.map do |attr|
      validate_attribute(attr)
    end
  end

  def validate_attribute(attr)
    unless attr.is_a?(Hash)
      raise ValidationError, "Attribute must be an object"
    end

    # Check exact key order
    unless attr.keys == ATTRIBUTE_KEYS
      raise ValidationError, "Invalid attribute keys or order. Expected: #{ATTRIBUTE_KEYS.join(',')}, got: #{attr.keys.join(',')}"
    end

    # Both must be strings - no coercion
    [
      validate_string(attr['trait_type'], 'trait_type'),
      validate_string(attr['value'], 'value')
    ]
  end

  # Encoders

  def build_create_collection_values(data)
    [
      data['name'],
      data['symbol'],
      data['max_supply'],
      data['description'],
      data['logo_image_uri'],
      data['banner_image_uri'],
      data['background_color'],
      data['website_link'],
      data['twitter_link'],
      data['discord_link'],
      # Append zero merkle root to satisfy contract struct shape
      ["".ljust(64, '0')].pack('H*')
    ]
  end

  def build_create_and_add_self_values(data)
    meta = data['metadata']
    item = data['item']

    # Metadata tuple with optional merkleRoot
    merkle_root = meta[:merkleRoot] || ["".ljust(64, '0')].pack('H*')
    metadata_tuple = [
      meta[:name],
      meta[:symbol],
      meta[:maxSupply],
      meta[:description],
      meta[:logoImageUri],
      meta[:bannerImageUri],
      meta[:backgroundColor],
      meta[:websiteLink],
      meta[:twitterLink],
      meta[:discordLink],
      merkle_root
    ]

    item_tuple = [
      item[:itemIndex],
      item[:name],
      item[:ethscriptionId],
      item[:backgroundColor],
      item[:description],
      item[:attributes],
      item[:merkleProof]
    ]

    [metadata_tuple, item_tuple]
  end

  def build_add_items_batch_values(data)
    # Transform items to array format for encoding
    items_array = data['items'].map do |item|
      [
        item[:itemIndex],
        item[:name],
        item[:ethscriptionId],
        item[:backgroundColor],
        item[:description],
        item[:attributes],
        item[:merkleProof]
      ]
    end

    [data['collection_id'], items_array]
  end

  def build_remove_items_values(data)
    [data['collection_id'], data['ethscription_ids']]
  end

  def build_edit_collection_values(data)
    values = [
      data['collection_id'],
      data['description'],
      data['logo_image_uri'],
      data['banner_image_uri'],
      data['background_color'],
      data['website_link'],
      data['twitter_link'],
      data['discord_link']
    ]

    # Append zero merkle root if not provided in payload (parser schema omits it)
    values << ["".ljust(64, '0')].pack('H*')
    values
  end

  def build_edit_collection_item_values(data)
    [
      data['collection_id'],
      data['item_index'],
      data['name'],
      data['background_color'],
      data['description'],
      data['attributes']
    ]
  end

  def build_lock_collection_values(data)
    # Single bytes32, not a tuple - but we need to return just the value
    data['collection_id']
  end

  def build_sync_ownership_values(data)
    [data['collection_id'], data['ethscription_ids']]
  end
end
