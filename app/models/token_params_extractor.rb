# Extracts token parameters from content URIs using strict regex validation
# Protocol uniqueness is based on exact text matching, so we validate the exact format
class TokenParamsExtractor
  # Constants
  DEFAULT_PARAMS = [''.b, ''.b, ''.b, 0, 0, 0].freeze
  UINT256_MAX = 2**256 - 1

  # Exact regex patterns for valid formats
  # Protocol must be "erc-20" (not captured since it's fixed)
  # Tick must be lowercase letters/numbers, max 28 chars
  # Numbers must be positive decimals without leading zeros
  DEPLOY_REGEX = /\Adata:,\{"p":"erc-20","op":"deploy","tick":"([a-z0-9]{1,28})","max":"(0|[1-9][0-9]*)","lim":"(0|[1-9][0-9]*)"\}\z/
  MINT_REGEX = /\Adata:,\{"p":"erc-20","op":"mint","tick":"([a-z0-9]{1,28})","id":"(0|[1-9][0-9]*)","amt":"(0|[1-9][0-9]*)"\}\z/

  def self.extract(content_uri)
    return DEFAULT_PARAMS unless content_uri.is_a?(String)

    # Try deploy format first
    if match = DEPLOY_REGEX.match(content_uri)
      tick = match[1]  # Group 1: tick
      max = match[2].to_i  # Group 2: max
      lim = match[3].to_i  # Group 3: lim

      # Validate uint256 bounds
      return DEFAULT_PARAMS if max > UINT256_MAX || lim > UINT256_MAX

      return ['deploy'.b, 'erc-20'.b, tick.b, max, lim, 0]
    end

    # Try mint format
    if match = MINT_REGEX.match(content_uri)
      tick = match[1]  # Group 1: tick
      id = match[2].to_i   # Group 2: id
      amt = match[3].to_i  # Group 3: amt

      # Validate uint256 bounds
      return DEFAULT_PARAMS if id > UINT256_MAX || amt > UINT256_MAX

      return ['mint'.b, 'erc-20'.b, tick.b, id, 0, amt]
    end

    # No match - return default
    DEFAULT_PARAMS
  end
end
