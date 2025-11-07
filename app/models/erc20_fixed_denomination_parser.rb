# Extracts fixed-denomination ERC-20 parameters from strict JSON inscriptions.
class Erc20FixedDenominationParser
  # Constants
  DEFAULT_PARAMS = [''.b, ''.b, ''.b].freeze
  UINT256_MAX = 2**256 - 1
  PROTOCOL = 'erc-20-fixed-denomination'.b

  # Exact regex patterns for valid formats
  # Protocol must be "erc-20" (legacy inscription) or the canonical identifier
  # Tick must be lowercase letters/numbers, max 28 chars
  # Numbers must be positive decimals without leading zeros
  PROTOCOL_PATTERN = '(?:erc-20|erc-20-fixed-denomination)'
  DEPLOY_REGEX = /\A\{"p":"#{PROTOCOL_PATTERN}","op":"deploy","tick":"([a-z0-9]{1,28})","max":"(0|[1-9][0-9]*)","lim":"(0|[1-9][0-9]*)"\}\z/
  MINT_REGEX = /\A\{"p":"#{PROTOCOL_PATTERN}","op":"mint","tick":"([a-z0-9]{1,28})","id":"(0|[1-9][0-9]*)","amt":"(0|[1-9][0-9]*)"\}\z/

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
    # Only support JSON source - no header parameters for ERC-20
    return DEFAULT_PARAMS unless source == :json
    return DEFAULT_PARAMS unless decoded_content.is_a?(String)

    # Try deploy format first
    if match = DEPLOY_REGEX.match(decoded_content)
      tick = match[1]  # Group 1: tick
      max = match[2].to_i  # Group 2: max
      lim = match[3].to_i  # Group 3: lim

      # Validate uint256 bounds
      return DEFAULT_PARAMS if max > UINT256_MAX || lim > UINT256_MAX

      encoded = Eth::Abi.encode(['(string,uint256,uint256)'], [[tick.b, max, lim]])
      return [PROTOCOL, 'deploy'.b, encoded.b]
    end

    # Try mint format
    if match = MINT_REGEX.match(decoded_content)
      tick = match[1]  # Group 1: tick
      id = match[2].to_i   # Group 2: id
      amt = match[3].to_i  # Group 3: amt

      # Validate uint256 bounds
      return DEFAULT_PARAMS if id > UINT256_MAX || amt > UINT256_MAX

      encoded = Eth::Abi.encode(['(string,uint256,uint256)'], [[tick.b, id, amt]])
      return [PROTOCOL, 'mint'.b, encoded.b]
    end

    # No match - return default
    DEFAULT_PARAMS
  end
end