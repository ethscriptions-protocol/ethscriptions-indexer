# Strict parser for the ERC-721 Ethscriptions collection protocol with canonical JSON validation
class Erc721EthscriptionsCollectionParser
  # Default return for invalid input
  DEFAULT_PARAMS = [''.b, ''.b, ''.b].freeze

  # Maximum value for uint256
  UINT256_MAX = 2**256 - 1

  # Operation schemas defining exact structure and ABI encoding
  OPERATION_SCHEMAS = {
    'create_collection' => {
      keys: %w[name symbol max_supply description logo_image_uri banner_image_uri background_color website_link twitter_link discord_link merkle_root],
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
        'discord_link' => :string,
        'merkle_root' => :bytes32
      }
    },
    # New combined create op name used by the contract; keep legacy alias below
    'create_collection_and_add_self' => {
      keys: %w[metadata item],
      # ((CollectionParams),(ItemData)) - ItemData mirrors ItemData struct (no ethscriptionId field)
      abi_type: '((string,string,uint256,string,string,string,string,string,string,string,bytes32),(uint256,string,string,string,(string,string)[],bytes32[]))',
      validators: {
        'metadata' => :collection_metadata,
        'item' => :single_item
      }
    },
    # Legacy alias retained for backwards compatibility
    'create_and_add_self' => {
      keys: %w[metadata item],
      abi_type: '((string,string,uint256,string,string,string,string,string,string,string,bytes32),(uint256,string,string,string,(string,string)[],bytes32[]))',
      validators: {
        'metadata' => :collection_metadata,
        'item' => :single_item
      }
    },
    # New single-item add op; keep legacy batch below for compatibility
    'add_self_to_collection' => {
      keys: %w[collection_id item],
      abi_type: '(bytes32,(uint256,string,string,string,(string,string)[],bytes32[]))',
      validators: {
        'collection_id' => :bytes32,
        'item' => :single_item
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
      keys: %w[collection_id description logo_image_uri banner_image_uri background_color website_link twitter_link discord_link merkle_root],
      abi_type: '(bytes32,string,string,string,string,string,string,string,bytes32)',
      validators: {
        'collection_id' => :bytes32,
        'description' => :string,
        'logo_image_uri' => :string,
        'banner_image_uri' => :string,
        'background_color' => :string,
        'website_link' => :string,
        'twitter_link' => :string,
        'discord_link' => :string,
        'merkle_root' => :bytes32
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
    }
  }.freeze

  ZERO_BYTES32 = ["".ljust(64, '0')].pack('H*').freeze
  ZERO_HEX_BYTES32 = '0x' + '0' * 64

  # Item keys for validation (merkle_proof always present, can be empty array)
  ITEM_KEYS = %w[item_index name background_color description attributes merkle_proof].freeze

  # Attribute keys for NFT metadata
  ATTRIBUTE_KEYS = %w[trait_type value].freeze

  class ValidationError < StandardError; end

  DEFAULT_ITEMS_PATH = ENV['COLLECTIONS_ITEMS_PATH'] || Rails.root.join('items_by_ethscription.json')
  DEFAULT_COLLECTIONS_PATH = ENV['COLLECTIONS_META_PATH'] || Rails.root.join('collections_by_name.json')

  def self.extract(content_uri, ethscription_id: nil)
    new.extract(content_uri, ethscription_id: ethscription_id)
  end

  def extract(content_uri, ethscription_id: nil)
    if ethscription_id
      normalized_id = normalize_id(ethscription_id)
      if normalized_id && (preplanned = build_import_encoded_params(normalized_id))
        return preplanned
      end
    end

    return DEFAULT_PARAMS unless valid_data_uri?(content_uri)

    begin
      json_str = DataUri.new(content_uri).decoded_data

      # TODO: make sure this is safe
      data = JSON.parse(json_str)
      return DEFAULT_PARAMS unless data.is_a?(Hash)
      return DEFAULT_PARAMS unless data['p'] == 'erc-721-ethscriptions-collection'

      operation = data['op']
      return DEFAULT_PARAMS unless OPERATION_SCHEMAS.key?(operation)

      schema = OPERATION_SCHEMAS[operation]
      expected_keys = ['p', 'op'] + schema[:keys]
      return DEFAULT_PARAMS unless data.keys == expected_keys

      encoding_data = data.reject { |k, _| k == 'p' || k == 'op' }
      encoded_data = encode_operation(operation, encoding_data, schema)
      ['erc-721-ethscriptions-collection'.b, operation.b, encoded_data.b]
    rescue JSON::ParserError, ValidationError => e
      Rails.logger.debug "Collections extraction failed: #{e.message}" if defined?(Rails)
      DEFAULT_PARAMS
    end
  end

  def normalize_id(value)
    case value
    when ByteString
      value.to_hex.downcase
    when String
      value.downcase
    else
      nil
    end
  end

  # -------------------- Import fallback --------------------

  # Returns [protocol, operation, encoded_data] or nil
  def build_import_encoded_params(id)
    data = self.class.load_import_data(
      items_path: DEFAULT_ITEMS_PATH,
      collections_path: DEFAULT_COLLECTIONS_PATH
    )

    item = data[:items_by_id][id]
    return nil unless item

    coll_name = item['collection_name']
    return nil unless coll_name

    leader_id = data[:leader_by_collection][coll_name]
    return nil unless leader_id

    item_index = data[:zero_index_by_id][id] || 0

    if id == leader_id
      raw_metadata = data[:collections_by_name][coll_name]
      return nil unless raw_metadata
      metadata = raw_metadata.merge(
        'merkle_root' => raw_metadata['merkle_root'] || ZERO_HEX_BYTES32
      )
      operation = 'create_collection_and_add_self'
      schema = OPERATION_SCHEMAS[operation]
      encoding_data = {
        'metadata' => build_metadata_object(metadata),
        'item' => build_item_object(item: item, item_index: item_index)
      }
      encoded_data = encode_operation(operation, encoding_data, schema)
      ['erc-721-ethscriptions-collection'.b, operation.b, encoded_data.b]
    else
      operation = 'add_self_to_collection'
      schema = OPERATION_SCHEMAS[operation]
      encoding_data = {
        'collection_id' => to_bytes32_hex(leader_id),
        'item' => build_item_object(item: item, item_index: item_index)
      }
      encoded_data = encode_operation(operation, encoding_data, schema)
      ['erc-721-ethscriptions-collection'.b, operation.b, encoded_data.b]
    end
  end

  class << self
    include Memery

    def load_import_data(items_path:, collections_path:)
      items = JSON.parse(File.read(items_path))
      collections = JSON.parse(File.read(collections_path))

      items_by_id = {}
      items.each { |k, v| items_by_id[k.to_s.downcase] = v }

      # Group items by collection and derive leader (min ethscription_number)
      groups = Hash.new { |h, k| h[k] = [] }
      items_by_id.each do |iid, it|
        cname = it['collection_name']
        next unless cname.is_a?(String) && !cname.empty?
        num = it['ethscription_number'].to_i
        groups[cname] << [iid, num]
      end

      leader_by_collection = {}
      groups.each do |cname, pairs|
        next if pairs.empty?
        leader_by_collection[cname] = pairs.min_by { |_id, num| num }[0]
      end

      # Normalize item indices to zero-based
      zero_index_by_id = {}
      groups.each do |_cname, pairs|
        explicit = pairs.map { |(iid, _)| [iid, items_by_id[iid]['index']] }
        explicit_indices = explicit.filter_map { |_iid, idx| idx if idx.is_a?(Integer) }
        if explicit_indices.size == pairs.size
          min_idx = explicit_indices.min
          offset = (min_idx == 0) ? 0 : 1
          explicit.each { |iid, idx| zero_index_by_id[iid] = [idx - offset, 0].max }
        else
          pairs.sort_by { |_iid, num| num }.each_with_index { |(iid, _), i| zero_index_by_id[iid] = i }
        end
      end

      {
        items_by_id: items_by_id,
        collections_by_name: collections,
        leader_by_collection: leader_by_collection,
        zero_index_by_id: zero_index_by_id
      }
    end
    memoize :load_import_data
  end

  # Build ordered JSON objects to match strict parser expectations
  def build_metadata_object(meta)
    name = safe_string(meta['name'])
    symbol = safe_string(meta['symbol'] || meta['slug'] || meta['name'])
    max_supply = safe_uint_string(meta['max_supply'] || meta['total_supply'] || 0)
    description = safe_string(meta['description'])
    logo_image_uri = safe_string(meta['logo_image_uri'])
    banner_image_uri = safe_string(meta['banner_image_uri'])
    background_color = safe_string(meta['background_color'])
    website_link = safe_string(meta['website_link'])
    twitter_link = safe_string(meta['twitter_link'])
    discord_link = safe_string(meta['discord_link'])

    result = OrderedHash[
      'name', name,
      'symbol', symbol,
      'max_supply', max_supply,
      'description', description,
      'logo_image_uri', logo_image_uri,
      'banner_image_uri', banner_image_uri,
      'background_color', background_color,
      'website_link', website_link,
      'twitter_link', twitter_link,
      'discord_link', discord_link
    ]
    merkle_root = meta.fetch('merkle_root')
    result['merkle_root'] = to_bytes32_hex(merkle_root)
    result
  end

  def build_item_object(item:, item_index:)
    attrs = Array(item['attributes']).map do |a|
      OrderedHash['trait_type', safe_string(a['trait_type']), 'value', safe_string(a['value'])]
    end

    proofs = item.key?('merkle_proof') ? Array(item['merkle_proof']) : []

    OrderedHash[
      'item_index', safe_uint_string(item_index),
      'name', safe_string(item['name']),
      'background_color', safe_string(item['background_color']),
      'description', safe_string(item['description']),
      'attributes', attrs,
      'merkle_proof', proofs
    ]
  end

  def to_bytes32_hex(val)
    h = safe_string(val).downcase
    raise ValidationError, "Invalid bytes32 hex: #{val}" unless h.match?(/\A0x[0-9a-f]{64}\z/)
    h
  end

  # Integer coercion helper for import computations
  def safe_uint(val)
    case val
    when Integer then val
    when String then (val =~ /\A\d+\z/ ? val.to_i : 0)
    else 0
    end
  end

  def safe_uint_string(val)
    n = case val
        when Integer then val
        when String then (val =~ /\A\d+\z/ ? val.to_i : 0)
        else 0
        end
    n = 0 if n.negative?
    n.to_s
  end

  def safe_string(val)
    val.nil? ? '' : val.to_s
  end

  def ordered_json(pairs)
    JSON.generate(OrderedHash[pairs.to_a.flatten])
  end

  class OrderedHash < ::Hash
    def self.[](*args)
      h = new
      args.each_slice(2) { |k, v| h[k] = v }
      h
    end
  end

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
    when 'create_collection_and_add_self', 'create_and_add_self'
      build_create_and_add_self_values(validated_data)
    when 'add_self_to_collection'
      build_add_self_to_collection_values(validated_data)
    when 'remove_items'
      build_remove_items_values(validated_data)
    when 'edit_collection'
      build_edit_collection_values(validated_data)
    when 'edit_collection_item'
      build_edit_collection_item_values(validated_data)
    when 'lock_collection'
      build_lock_collection_values(validated_data)
    else
      raise ValidationError, "Unknown operation: #{operation}"
    end

    # Use ABI type from schema for encoding
    begin
      Eth::Abi.encode([schema[:abi_type]], [values])
    rescue Encoding::CompatibilityError => e
      Rails.logger.error "=== Collection ABI Encoding Error ==="
      Rails.logger.error "Error: #{e.message}"
      Rails.logger.error "operation: #{operation}"
      Rails.logger.error "schema abi_type: #{schema[:abi_type]}"
      Rails.logger.error "values inspection:"
      log_encoding_details(values)
      raise
    end
  end
  
  def log_encoding_details(obj, indent = 0)
    prefix = "  " * indent
    case obj
    when Array
      Rails.logger.error "#{prefix}Array[#{obj.size}]:"
      obj.each_with_index do |item, idx|
        Rails.logger.error "#{prefix}  [#{idx}]:"
        log_encoding_details(item, indent + 2)
      end
    when String
      Rails.logger.error "#{prefix}String: #{obj.inspect[0..100]}, encoding: #{obj.encoding.name}, bytesize: #{obj.bytesize}"
    else
      Rails.logger.error "#{prefix}#{obj.class}: #{obj.inspect[0..100]}"
    end
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
    value.b
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
    expected_keys = %w[name symbol max_supply description logo_image_uri banner_image_uri background_color website_link twitter_link discord_link merkle_root]
    unless value.keys == expected_keys
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
      merkleRoot: validate_bytes32(value['merkle_root'], 'merkle_root')
    }
  end

  def validate_item(item)
    unless item.is_a?(Hash)
      raise ValidationError, "Item must be an object"
    end

    unless item.keys == ITEM_KEYS
      expected = "[#{ITEM_KEYS.join(', ')}]"
      raise ValidationError, "Invalid item keys or order. Expected: #{expected}, got: [#{item.keys.join(', ')}]"
    end

    {
      itemIndex: validate_uint256(item['item_index'], 'item_index'),
      name: validate_string(item['name'], 'name'),
      backgroundColor: validate_string(item['background_color'], 'background_color'),
      description: validate_string(item['description'], 'description'),
      attributes: validate_attributes_array(item['attributes'], 'attributes'),
      merkleProof: validate_bytes32_array(item['merkle_proof'], 'merkle_proof')
    }
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
      data['merkle_root']
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
      item[:backgroundColor],
      item[:description],
      item[:attributes],
      item[:merkleProof]
    ]

    [metadata_tuple, item_tuple]
  end

  def build_add_self_to_collection_values(data)
    item = data['item']
    item_tuple = [
      item[:itemIndex],
      item[:name],
      item[:backgroundColor],
      item[:description],
      item[:attributes],
      item[:merkleProof]
    ]
    [data['collection_id'], item_tuple]
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

    values << data['merkle_root']
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
end
