# Unified protocol parser that delegates to specific protocol parsers
class ProtocolParser
  # Default return value for all parsers - unified 3-element format
  DEFAULT_PARAMS = [''.b, ''.b, ''.b].freeze

  # Protocol name to parser class mapping
  PROTOCOL_PARSERS = {
    'word-domains' => WordDomainsParser,
    'erc-20' => Erc20FixedDenominationParser,
    'erc-20-fixed-denomination' => Erc20FixedDenominationParser,
    'erc-721-ethscriptions-collection' => Erc721EthscriptionsCollectionParser
  }.freeze

  def self.extract(content_uri, eth_transaction: nil, ethscription_id: nil)
    # Parse data URI and extract protocol info
    parsed = parse_data_uri_and_protocol(content_uri)

    # Special case: plain word-domains registration (data:,word) has no protocol markers
    if parsed.nil?
      # If we have an ethscription_id, try import fallback for collections regardless of content
      if ethscription_id
        # Get decoded content for import fallback
        decoded_content = nil
        if content_uri.is_a?(String) && DataUri.valid?(content_uri)
          data_uri = DataUri.new(content_uri)
          decoded_content = data_uri.decoded_data
        end

        # Try collections parser for import fallback with any content
        # Ensure decoded_content is binary to avoid encoding issues
        encoded = Erc721EthscriptionsCollectionParser.validate_and_encode(
          decoded_content: (decoded_content || '').b,
          operation: nil,
          params: {},
          source: :json,
          ethscription_id: ethscription_id,
          eth_transaction: eth_transaction
        )

        if encoded != DEFAULT_PARAMS
          protocol, operation, encoded_data = encoded
          return {
            type: :erc721_ethscriptions_collection,
            protocol: protocol,
            operation: operation,
            params: nil,
            encoded_params: encoded_data
          }
        end
      end

      return try_plain_word_domains(content_uri)
    end

    # Direct routing - no "try" needed since we know the protocol
    parser_class = PROTOCOL_PARSERS[parsed[:protocol_name]]
    return nil unless parser_class

    # Call the same method on all parsers with unified interface
    encoded = parser_class.validate_and_encode(
      decoded_content: parsed[:decoded_content],
      operation: parsed[:operation],
      params: parsed[:params],
      source: parsed[:source],
      ethscription_id: ethscription_id,
      eth_transaction: eth_transaction
    )

    # Check if parsing succeeded
    return nil if encoded == DEFAULT_PARAMS

    protocol, operation, encoded_data = encoded

    # Derive type from parser class name
    type = parser_class.name.underscore.sub(/_parser$/, '').to_sym

    {
      type: type,
      protocol: protocol,
      operation: operation,
      params: nil,
      encoded_params: encoded_data
    }
  end

  # Get protocol data formatted for L2 calldata
  # Returns [protocol, operation, encoded_data] for contract consumption
  def self.for_calldata(content_uri, eth_transaction: nil, ethscription_id: nil)
    # Support both for backward compatibility
    ethscription_id ||= eth_transaction&.transaction_hash
    result = extract(content_uri, eth_transaction: eth_transaction, ethscription_id: ethscription_id)

    if result.nil?
      # No protocol detected - return empty protocol params
      DEFAULT_PARAMS
    else
      # All parsers return the same format, so we can just extract directly
      [result[:protocol], result[:operation], result[:encoded_params]]
    end
  end

  private

  # Parse data URI and extract protocol information from JSON body or headers
  # Returns hash with: decoded_content, protocol_name, operation, params, source
  # Note: content_hash removed - parsers compute their own if needed
  def self.parse_data_uri_and_protocol(content_uri)
    return nil unless content_uri.is_a?(String)
    return nil unless DataUri.valid?(content_uri)

    data_uri = DataUri.new(content_uri)
    decoded_content = data_uri.decoded_data
    return nil unless decoded_content.is_a?(String)

    # Try to extract protocol from JSON body
    json_protocol = extract_json_protocol(decoded_content)

    # Try to extract protocol from headers
    header_protocol = extract_header_protocol(data_uri)

    # Fail if both present (ambiguous)
    return nil if json_protocol && header_protocol

    # Get protocol info from whichever source exists
    protocol_info = json_protocol || header_protocol
    return nil unless protocol_info

    {
      decoded_content: decoded_content,
      protocol_name: protocol_info[:protocol],
      operation: protocol_info[:operation],
      params: protocol_info[:params],
      source: protocol_info[:source]
    }
  end

  # Extract protocol info from JSON body
  def self.extract_json_protocol(decoded_content)
    return nil unless decoded_content.lstrip.start_with?('{')

    data = JSON.parse(decoded_content)
    return nil unless data.is_a?(Hash)

    protocol = data['p'] || data['protocol']
    operation = data['op'] || data['operation'] || data['type']

    return nil unless protocol.is_a?(String) && operation.is_a?(String)

    # Return protocol info with full JSON data as params
    {
      protocol: protocol,
      operation: operation,
      params: data,
      source: :json
    }
  rescue JSON::ParserError
    nil
  end

  # Extract protocol info from data URI headers (;p=...;op=...;d=...)
  def self.extract_header_protocol(data_uri)
    params_map = parse_parameters(data_uri.parameters)

    # Must have exactly one 'p' and exactly one 'op'
    p_values = params_map['p']
    op_values = params_map['op']

    return nil unless p_values&.length == 1 && op_values&.length == 1

    protocol = p_values.first
    operation = op_values.first

    # Validate protocol and operation format (lowercase, alphanumeric + dash/underscore, 1-50 chars)
    return nil unless protocol.match?(/\A[a-z0-9\-_]{1,50}\z/)
    return nil unless operation.match?(/\A[a-z0-9\-_]{1,50}\z/)

    # Optional data parameter (d= or data=) with base64-encoded JSON
    d_values = (params_map['d'] || []) + (params_map['data'] || [])
    return nil if d_values.length > 1  # Only zero or one allowed

    params_hash = {}
    if d_values.length == 1
      begin
        raw = Base64.strict_decode64(d_values.first)
        parsed = JSON.parse(raw)
        params_hash = parsed if parsed.is_a?(Hash)
      rescue ArgumentError, JSON::ParserError
        return nil  # Invalid base64 or JSON
      end
    end

    {
      protocol: protocol,
      operation: operation,
      params: params_hash,
      source: :header
    }
  end

  # Parse data URI parameters into a hash of arrays (supporting multiple values per key)
  def self.parse_parameters(parameters)
    map = Hash.new { |h, k| h[k] = [] }

    parameters.each do |seg|
      next if seg.to_s.empty?

      if (eq = seg.index('='))
        key = seg[0...eq].strip.downcase
        val = seg[(eq + 1)..].to_s.strip
        map[key] << val
      end
      # Ignore bare flags (e.g., base64, rule=esip6)
    end

    map
  end

  def self.try_plain_word_domains(content_uri)
    # Try to parse as plain word-domains registration (data:,word)
    return nil unless content_uri.is_a?(String)
    return nil unless DataUri.valid?(content_uri)

    data_uri = DataUri.new(content_uri)
    decoded_content = data_uri.decoded_data
    return nil unless decoded_content.is_a?(String)

    # For plain word-domains: must have blank mimetype and no parameters
    # Also reject empty content (like 'data:,')
    return nil if decoded_content.strip.empty?
    mt = data_uri.mimetype.to_s
    return nil unless (mt.empty? || mt == 'text/plain') && data_uri.parameters.empty?

    # Special handling for plain word-domains
    encoded = WordDomainsParser.validate_and_encode(
      decoded_content: decoded_content,
      operation: nil,  # No operation for plain text
      params: {},
      source: :plain,
      ethscription_id: nil
    )

    return nil if encoded == DEFAULT_PARAMS

    protocol, operation, encoded_data = encoded

    {
      type: :word_domains,
      protocol: protocol,
      operation: operation,
      params: nil,
      encoded_params: encoded_data
    }
  end
end