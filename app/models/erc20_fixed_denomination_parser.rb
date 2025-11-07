# Extracts fixed-denomination ERC-20 parameters from strict JSON inscriptions.
class Erc20FixedDenominationParser
  # Constants
  DEFAULT_PARAMS = [''.b, ''.b, ''.b, 0, 0, 0].freeze
  UINT256_MAX = 2**256 - 1
  
  # Exact regex patterns for valid formats
  # Protocol must be "erc-20" (legacy inscription) or the canonical identifier
  # Tick must be lowercase letters/numbers, max 28 chars
  # Numbers must be positive decimals without leading zeros
  PROTOCOL_PATTERN = '(?:erc-20|erc-20-fixed-denomination)'
  DEPLOY_REGEX = /\Adata:,\{"p":"#{PROTOCOL_PATTERN}","op":"deploy","tick":"([a-z0-9]{1,28})","max":"(0|[1-9][0-9]*)","lim":"(0|[1-9][0-9]*)"\}\z/
  MINT_REGEX = /\Adata:,\{"p":"#{PROTOCOL_PATTERN}","op":"mint","tick":"([a-z0-9]{1,28})","id":"(0|[1-9][0-9]*)","amt":"(0|[1-9][0-9]*)"\}\z/

  def self.extract(content_uri)
    return DEFAULT_PARAMS unless content_uri.is_a?(String)

    # Try deploy format first
    if match = DEPLOY_REGEX.match(content_uri)
      tick = match[1]  # Group 1: tick
      max = match[2].to_i  # Group 2: max
      lim = match[3].to_i  # Group 3: lim

      # Validate uint256 bounds
      return DEFAULT_PARAMS if max > UINT256_MAX || lim > UINT256_MAX

      return ['deploy'.b, 'erc-20-fixed-denomination'.b, tick.b, max, lim, 0]
    end

    # Try mint format
    if match = MINT_REGEX.match(content_uri)
      tick = match[1]  # Group 1: tick
      id = match[2].to_i   # Group 2: id
      amt = match[3].to_i  # Group 3: amt

      # Validate uint256 bounds
      return DEFAULT_PARAMS if id > UINT256_MAX || amt > UINT256_MAX

      return ['mint'.b, 'erc-20-fixed-denomination'.b, tick.b, id, 0, amt]
    end

    # No match - return default
    DEFAULT_PARAMS
  end

  # Returns a hash representation of params that downstream services expect.
  def self.structured_params(params)
    op, _protocol, tick, val1, val2, val3 = params

    case op
    when 'deploy'.b
      {
        op: op,
        tick: tick,
        max: val1,
        lim: val2,
        amt: 0
      }
    when 'mint'.b
      {
        op: op,
        tick: tick,
        id: val1,
        amt: val3
      }
    else
      nil
    end
  end

  # Encodes params into the ABI tuple required by the manager contract.
  def self.encode_calldata(params)
    op, _protocol, tick, val1, val2, val3 = params

    if op == 'deploy'.b
      Eth::Abi.encode(['(string,uint256,uint256)'], [[tick.b, val1, val2]])
    elsif op == 'mint'.b
      Eth::Abi.encode(['(string,uint256,uint256)'], [[tick.b, val1, val3]])
    else
      ''.b
    end
  end
end
