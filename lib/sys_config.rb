module SysConfig
  extend self
  
  # Fixed L2 parameters
  L2_BLOCK_GAS_LIMIT = 10_000_000_000  # Fixed gas limit (gas is never charged)
  L2_BLOCK_TIME = 12
  
  # System addresses (matching Solidity contracts)
  SYSTEM_ADDRESS = Address20.from_hex("0xdeaddeaddeaddeaddeaddeaddeaddeaddead0001")
  L1_INFO_ADDRESS = Address20.from_hex("0x4200000000000000000000000000000000000015")
  ETHSCRIPTIONS_ADDRESS = Address20.from_hex("0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE")
  TOKEN_MANAGER_ADDRESS = Address20.from_hex("0x3300000000000000000000000000000000000002")
  
  # Deposit transaction domains
  USER_DEPOSIT_SOURCE_DOMAIN = 0
  L1_INFO_DEPOSIT_SOURCE_DOMAIN = 1
  
  def ethscriptions_contract_address
    ETHSCRIPTIONS_ADDRESS
  end
  
  def token_manager_contract_address
    TOKEN_MANAGER_ADDRESS
  end
  
  def block_gas_limit(block = nil)
    L2_BLOCK_GAS_LIMIT
  end
  
  def l1_genesis_block_number
    ENV.fetch('L1_GENESIS_BLOCK').to_i
  end
  
  def current_l1_network
    ChainIdManager.current_l1_network
  end
  
  # ESIP fork block numbers
  def esip1_enabled?(block_number)
    on_testnet? || block_number >= 17672762
  end
  
  def esip2_enabled?(block_number)
    on_testnet? || block_number >= 17764910
  end
  
  def esip3_enabled?(block_number)
    on_testnet? || block_number >= 18130000
  end
  
  def esip5_enabled?(block_number)
    on_testnet? || block_number >= 18330000
  end
  
  def esip7_enabled?(block_number)
    on_testnet? || block_number >= 19376500
  end
  
  def esip8_enabled?(block_number)
    on_testnet? || block_number >= 19526000
  end
  
  def on_testnet?
    !ChainIdManager.on_mainnet?
  end
end