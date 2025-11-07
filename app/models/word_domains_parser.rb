# Parser for legacy word-only domain inscriptions and related operations.
class WordDomainsParser
  DEFAULT_PARAMS = [''.b, ''.b, ''.b].freeze

  PROTOCOL_STRING = 'word-domains'.freeze
  PROTOCOL = PROTOCOL_STRING.b
  REGISTER_OP = 'register'.b
  SET_PRIMARY_OP = 'set_primary'.b

  NAME_REGEX = /\A[a-z0-9_]{1,30}\z/.freeze

  # Validate and encode protocol params
  # Unified interface - accepts all possible parameters, uses what it needs
  def self.validate_and_encode(decoded_content:, operation:, params:, source:, ethscription_id: nil, **_extras)
    new.validate_and_encode(
      decoded_content: decoded_content,
      operation: operation,
      params: params,
      source: source
    )
  end

  def validate_and_encode(decoded_content:, operation:, params:, source:)
    case source
    when :json
      # JSON-based protocol (from payload)
      validate_json_operation(operation, params)
    when :plain
      # Legacy plain text registration: data:,word
      # The decoded_content should match our name regex
      return DEFAULT_PARAMS unless decoded_content.is_a?(String)
      return DEFAULT_PARAMS unless NAME_REGEX.match?(decoded_content)

      encoded = Eth::Abi.encode(['string'], [decoded_content])
      [PROTOCOL, REGISTER_OP, encoded.b]
    else
      # Word domains do not support header parameters
      DEFAULT_PARAMS
    end
  end

  private

  def validate_json_operation(operation, params)
    case operation
    when 'register'
      validate_register_operation(params)
    when 'set_primary'
      validate_set_primary_operation(params)
    else
      DEFAULT_PARAMS
    end
  end

  def validate_register_operation(params)
    name = params['name']
    return DEFAULT_PARAMS unless name.is_a?(String)
    return DEFAULT_PARAMS unless NAME_REGEX.match?(name)

    encoded = Eth::Abi.encode(['string'], [name])
    [PROTOCOL, REGISTER_OP, encoded.b]
  end

  def validate_set_primary_operation(params)
    name = params['name']
    return DEFAULT_PARAMS unless name.is_a?(String)
    # Set primary allows blank to unset primary
    return DEFAULT_PARAMS unless name.empty? || NAME_REGEX.match?(name)

    encoded = Eth::Abi.encode(['string'], [name])
    [PROTOCOL, SET_PRIMARY_OP, encoded.b]
  end
end
