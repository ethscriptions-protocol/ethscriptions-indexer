# Unified protocol parser that delegates to specific protocol parsers
class ProtocolParser
  # Default return values to check if extraction succeeded
  TOKEN_DEFAULT_PARAMS = Erc20FixedDenominationParser::DEFAULT_PARAMS
  COLLECTIONS_DEFAULT_PARAMS = Erc721EthscriptionsCollectionParser::DEFAULT_PARAMS

  def self.extract(content_uri, ethscription_id: nil)
    # Try parsers in order of specificity
    # 1. Token protocol (most strict - exact character position matters)
    # 2. Collections protocol (strict - exact key order required)

    # Try token parser first (most strict)
    result = try_token_parser(content_uri)
    return result if result

    # Try collections parser next (if enabled)
    result = try_collections_parser(content_uri, ethscription_id: ethscription_id)
    return result if result

    # No protocol could be extracted
    nil
  end

  private

  def self.try_token_parser(content_uri)
    # Erc20FixedDenominationParser uses strict regex and returns DEFAULT_PARAMS if no match
    # This enforces non-ESIP6 and exact JSON formatting implicitly.
    params = Erc20FixedDenominationParser.extract(content_uri)

    # Check if extraction succeeded (returns non-default params)
    return nil if params == TOKEN_DEFAULT_PARAMS

    {
      type: :erc20_fixed_denomination,
      protocol: 'erc-20-fixed-denomination',
      operation: params[0], # 'deploy' or 'mint'
      params: params,
      encoded_params: Erc20FixedDenominationParser.structured_params(params)
    }
  end

  def self.try_collections_parser(content_uri, ethscription_id: nil)
    # Erc721EthscriptionsCollectionParser returns [''.b, ''.b, ''.b] if no match
    params = Erc721EthscriptionsCollectionParser.extract(
      content_uri,
      ethscription_id: ethscription_id
    )

    return nil if params == COLLECTIONS_DEFAULT_PARAMS

    protocol, operation, encoded_data = params

    # Check if extraction succeeded
    if protocol != ''.b && operation != ''.b
      {
        type: :erc721_ethscriptions_collection,
        protocol: protocol,
        operation: operation,
        params: nil, # Collections doesn't return decoded params
        encoded_params: encoded_data
      }
    else
      nil
    end
  end

  # Get protocol data formatted for L2 calldata
  # Returns [protocol, operation, encoded_data] for contract consumption
  def self.for_calldata(content_uri, ethscription_id: nil)
    result = extract(content_uri, ethscription_id: ethscription_id)

    if result.nil?
      # No protocol detected - return empty protocol params
      [''.b, ''.b, ''.b]
    elsif result[:type] == :erc20_fixed_denomination
      # Fixed denomination ERC-20 protocol - return in ABI-ready format
      protocol = result[:protocol].b
      operation = result[:operation]
      # For tokens, encode the params properly
      encoded_data = Erc20FixedDenominationParser.encode_calldata(result[:params])
      [protocol, operation, encoded_data]
    elsif result[:type] == :erc721_ethscriptions_collection
      # Collections protocol - already has encoded data
      [result[:protocol], result[:operation], result[:encoded_params]]
    else
      # Unknown parser type - return empty protocol params
      [''.b, ''.b, ''.b]
    end
  end

end
