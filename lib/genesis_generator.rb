class GenesisGenerator
  def initialize(quiet: false)
    @quiet = quiet
  end

  def generate_full_genesis_json(l1_network_name:, l1_genesis_block_number:)
    config = {
      chainId: 0xeeee,
      homesteadBlock: 0,
      eip150Block: 0,
      eip155Block: 0,
      eip158Block: 0,
      byzantiumBlock: 0,
      constantinopleBlock: 0,
      petersburgBlock: 0,
      istanbulBlock: 0,
      muirGlacierBlock: 0,
      berlinBlock: 0,
      londonBlock: 0,
      mergeForkBlock: 0,
      mergeNetsplitBlock: 0,
      shanghaiTime: 0,
      cancunTime: cancun_timestamp(l1_network_name),
      terminalTotalDifficulty: 0,
      terminalTotalDifficultyPassed: true,
      bedrockBlock: 0,
      regolithTime: 0,
      canyonTime: 0,
      ecotoneTime: 0,
      fjordTime: 0,
      deltaTime: 0,
      optimism: {
        eip1559Elasticity: 3,
        eip1559Denominator: 8,
        eip1559DenominatorCanyon: 8
      }
    }
    
    timestamp, mix_hash = get_timestamp_and_mix_hash(l1_genesis_block_number)
    
    {
      config: config,
      timestamp: "0x#{timestamp.to_s(16)}",
      extraData: "0xb1bdb91f010c154dd04e5c11a6298e91472c27a347b770684981873a6408c11c",
      gasLimit: "0x#{SysConfig::L2_BLOCK_GAS_LIMIT.to_s(16)}",
      difficulty: "0x0",
      mixHash: mix_hash,
      alloc: generate_alloc_for_genesis(l1_network_name: l1_network_name)
    }
  end
  
  def get_timestamp_and_mix_hash(l1_block_number)
    l1_block_result = EthRpcClient.l1.get_block(l1_block_number)
    timestamp = l1_block_result['timestamp'].to_i(16)
    mix_hash = l1_block_result['mixHash']
    [timestamp, mix_hash]
  end

  def cancun_timestamp(l1_network_name)
    {
      "mainnet" => 1710338135,
      "sepolia" => 1706655072,
      "hoodi" => 0
    }.fetch(l1_network_name)
  end
  
  def generate_alloc_for_genesis(l1_network_name:)
    # Run forge script to generate allocations
    run_forge_genesis_script!
    
    # Use the allocations from forge script
    allocs_file = Rails.root.join('contracts', 'genesis-allocs.json')
    
    unless File.exist?(allocs_file)
      raise "Genesis allocations file not found at #{allocs_file}. Forge script failed!"
    end
    
    log "Loading allocations from #{allocs_file}..."
    JSON.parse(File.read(allocs_file))
  end
  
  def run_forge_genesis_script!
    log "Running Forge L2Genesis script..."
    log "=" * 80
    
    contracts_dir = Rails.root.join('contracts')
    script_path = contracts_dir.join('script', 'L2Genesis.s.sol')
    
    unless File.exist?(script_path)
      raise "L2Genesis script not found at #{script_path}"
    end
    
    should_perform_genesis_import = ENV.fetch('PERFORM_GENESIS_IMPORT', 'true') == 'true'

    # Build the forge script command
    cmd = "cd #{contracts_dir} && PERFORM_GENESIS_IMPORT=#{should_perform_genesis_import} forge script '#{script_path}:L2Genesis'"
    
    log "Executing: #{cmd}"
    log nil
    
    # Run the command and capture output
    output = `#{cmd} 2>&1`
    success = $?.success?

    log output unless @quiet

    unless success
      raise "Forge script failed! Exit code: #{$?.exitstatus}"
    end

    log "✅ Forge script completed successfully", force: true
    log "=" * 80
    log nil
  end
  
  def run!
    l1_network_name = ENV.fetch('L1_NETWORK')
    l1_genesis_block_number = ENV.fetch('L1_GENESIS_BLOCK').to_i
    
    log "=" * 80
    log "Generating Full Genesis File"
    log "=" * 80
    log "L1 Network: #{l1_network_name}"
    log "L1 Genesis Block: #{l1_genesis_block_number}"
    log nil
    
    # Generate the full genesis
    genesis = generate_full_genesis_json(
      l1_network_name: l1_network_name,
      l1_genesis_block_number: l1_genesis_block_number
    )
    
    geth_dir = ENV.fetch('LOCAL_GETH_DIR')

    # Write to file
    output_file = File.join(geth_dir, "genesis-files", "ethscriptions-#{l1_network_name}.json")
    File.write(output_file, JSON.pretty_generate(genesis))
    
    log "✅ Genesis file written to: #{output_file}", force: true
    log nil
    log "Genesis Configuration:"
    log "  Chain ID: 0x#{genesis[:config][:chainId].to_s(16)}"
    log "  Timestamp: #{genesis[:timestamp]} (#{Time.at(genesis[:timestamp].to_i(16))})"
    log "  Mix Hash: #{genesis[:mixHash]}"
    log "  Gas Limit: #{genesis[:gasLimit]}"
    log "  Allocations: #{genesis[:alloc].keys.count} accounts"
    log nil
    log "To initialize Geth with this genesis:"
    log "  geth init --datadir ./datadir genesis.json"
    
    output_file
  end
  
  private

  def log(message, force: false)
    return if @quiet && !force

    if message.nil?
      puts
    else
      puts message
    end
  end
end

# Run the generator
# generator = GenesisGenerator.new
# generator.run!