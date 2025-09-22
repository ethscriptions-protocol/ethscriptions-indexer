namespace :genesis do
  desc "Generate L2 genesis file with Forge script and configurations"
  task :generate => :environment do
    # Validate required environment variables
    required_vars = ['L1_NETWORK', 'L1_GENESIS_BLOCK', 'LOCAL_GETH_DIR']
    missing_vars = required_vars.select { |var| ENV[var].nil? }
    
    if missing_vars.any?
      puts "❌ Missing required environment variables: #{missing_vars.join(', ')}"
      puts
      puts "Usage:"
      puts "  L1_NETWORK=mainnet L1_GENESIS_BLOCK=123456 LOCAL_GETH_DIR=/path/to/geth rake genesis:generate"
      puts
      puts "Options:"
      puts "  L1_NETWORK        - Network name (mainnet, sepolia, hoodi)"
      puts "  L1_GENESIS_BLOCK  - L1 block number for genesis"
      puts "  LOCAL_GETH_DIR    - Directory where genesis.json will be saved"
      puts "  USE_STATE_DUMP    - Set to 'true' to use Geth state dump instead of Forge script"
      exit 1
    end
    
    # Run the genesis generator
    generator = GenesisGenerator.new
    generator.run!
  end
  
  desc "Generate L2 genesis allocations only (runs Forge script)"
  task :allocations => :environment do
    puts "Generating L2 genesis allocations..."
    puts "=" * 80
    
    contracts_dir = Rails.root.join('contracts')
    script_path = contracts_dir.join('script', 'L2Genesis.s.sol')
    
    unless File.exist?(script_path)
      puts "❌ L2Genesis script not found at #{script_path}"
      exit 1
    end
    
    # Build and run the forge script command
    cmd = "cd #{contracts_dir} && forge script '#{script_path}:L2Genesis'"
    
    puts "Executing: #{cmd}"
    puts
    
    success = system(cmd)
    
    unless success
      puts "❌ Forge script failed!"
      exit 1
    end
    
    allocs_file = contracts_dir.join('genesis-allocs.json')
    if File.exist?(allocs_file)
      puts
      puts "✅ Genesis allocations generated successfully!"
      puts "📄 File: #{allocs_file}"
      
      # Show summary
      allocs = JSON.parse(File.read(allocs_file))
      puts "📊 Total accounts: #{allocs.keys.count}"
      
      # Show some key accounts
      key_accounts = {
        "0x4200000000000000000000000000000000000000" => "L2ToL1MessagePasser",
        "0x4200000000000000000000000000000000000001" => "L2CrossDomainMessenger",
        "0x4200000000000000000000000000000000000002" => "L2StandardBridge",
        "0x4200000000000000000000000000000000000015" => "L1Block",
        "0xE7e7e7E7E7E7e7e7e7E7E7E7e7E7E7e7E7e7e700" => "Ethscriptions",
        "0xE7e7e7E7E7E7e7e7e7E7E7E7e7E7E7e7E7e7e701" => "TokenManager",
        "0xE7e7e7E7E7E7e7e7e7E7E7E7e7E7E7e7E7e7e702" => "EthscriptionsProver",
        "0xE7e7e7E7E7E7e7e7e7E7E7E7e7E7E7e7E7e7e703" => "ERC20Template"
      }
      
      puts
      puts "Key accounts:"
      key_accounts.each do |address, name|
        if allocs[address.downcase]
          puts "  ✓ #{name}: #{address}"
        else
          puts "  ✗ #{name}: #{address} (missing)"
        end
      end
    else
      puts "❌ Genesis allocations file was not created!"
      exit 1
    end
  end
  
  desc "Show current genesis configuration"
  task :info => :environment do
    geth_dir = ENV['LOCAL_GETH_DIR']
    
    if geth_dir.nil?
      puts "❌ LOCAL_GETH_DIR not set"
      exit 1
    end
    
    genesis_file = File.join(geth_dir, 'genesis.json')
    
    unless File.exist?(genesis_file)
      puts "❌ Genesis file not found at #{genesis_file}"
      puts "   Run 'rake genesis:generate' first"
      exit 1
    end
    
    genesis = JSON.parse(File.read(genesis_file))
    
    puts "Genesis Configuration"
    puts "=" * 80
    puts "File: #{genesis_file}"
    puts
    puts "Chain Configuration:"
    puts "  Chain ID: 0x#{genesis['config']['chainId'].to_s(16)}"
    puts "  Timestamp: #{genesis['timestamp']} (#{Time.at(genesis['timestamp'].to_i(16))})"
    puts "  Gas Limit: #{genesis['gasLimit']}"
    puts "  Mix Hash: #{genesis['mixHash']}"
    puts
    puts "Hardforks:"
    config = genesis['config']
    %w[homestead byzantium constantinople petersburg istanbul berlin london].each do |fork|
      block_key = "#{fork}Block"
      if config[block_key]
        puts "  #{fork.capitalize}: block #{config[block_key]}"
      end
    end
    
    %w[shanghai cancun].each do |fork|
      time_key = "#{fork}Time"
      if config[time_key]
        puts "  #{fork.capitalize}: time #{config[time_key]}"
      end
    end
    
    if config['optimism']
      puts
      puts "Optimism Configuration:"
      config['optimism'].each do |k, v|
        puts "  #{k}: #{v}"
      end
    end
    
    puts
    puts "Allocations: #{genesis['alloc'].keys.count} accounts"
    
    # Show balances for key accounts
    key_accounts = {
      "0xe7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e700" => "Ethscriptions",
      "0xe7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e701" => "TokenManager",
      "0xe7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e702" => "EthscriptionsProver"
    }
    
    puts
    puts "Key Ethscriptions Contracts:"
    key_accounts.each do |address, name|
      account = genesis['alloc'][address]
      if account
        balance = account['balance'] ? "Balance: #{account['balance']}" : "No balance"
        code = account['code'] ? "Code: #{account['code'].length} chars" : "No code"
        puts "  #{name}: #{balance}, #{code}"
      else
        puts "  #{name}: Not found"
      end
    end
  end
end