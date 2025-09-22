require 'rails_helper'
require_relative '../support/geth_test_helper'

RSpec.describe "Mainnet Block Import", type: :integration do
  before(:all) do
    # Load mainnet environment
    Dotenv.load('.env.mainnet')
    
    # Setup Geth instance
    GethTestHelper.setup_rspec_geth
    
    # Wait for Geth to be ready
    sleep 2
  end
  
  after(:all) do
    GethTestHelper.teardown_rspec_geth
  end
  
  describe "importing genesis block from mainnet" do
    it "successfully imports the L1 genesis block" do
      # Get the L1 genesis block number from environment
      l1_genesis_block_number = ENV.fetch('L1_GENESIS_BLOCK').to_i
      
      puts "Importing L1 genesis block #{l1_genesis_block_number} from mainnet..."
      
      # Initialize the block importer
      importer = EthBlockImporter.new
      
      # Create initial L2 genesis block
      l2_genesis_block = EthscriptionsBlock.new(
        number: 0,
        timestamp: SysConfig.genesis_timestamp,
        eth_block_number: l1_genesis_block_number,
        eth_block_timestamp: nil, # Will be set from L1 block
        sequence_number: 0
      )
      
      # Fetch the L1 block
      l1_block_data = EthRpcClient.l1.get_block(l1_genesis_block_number)
      expect(l1_block_data).not_to be_nil
      
      l1_eth_block = EthBlock.from_rpc_result(l1_block_data)
      puts "L1 Block #{l1_genesis_block_number}:"
      puts "  Hash: #{l1_eth_block.block_hash}"
      puts "  Timestamp: #{l1_eth_block.timestamp}"
      puts "  Transactions: #{l1_eth_block.transactions_count}"
      
      # Create the first Ethscriptions block from the L1 block
      ethscriptions_block = EthscriptionsBlock.from_eth_block(l1_eth_block)
      
      # Get block receipts to parse potential Ethscriptions
      receipts = EthRpcClient.l1.get_block_receipts(l1_genesis_block_number)
      
      # Parse Ethscription transactions from the L1 block
      ethscription_txs = EthTransaction.ethscription_txs_from_rpc_results(
        l1_block_data,
        receipts,
        ethscriptions_block
      )
      
      puts "Found #{ethscription_txs.length} Ethscription transactions"
      
      if ethscription_txs.any?
        ethscription_txs.each do |tx|
          puts "  - Operation: #{tx.ethscription_operation}"
          puts "    Data: #{tx.ethscription_data}"
        end
      end
      
      # Propose the block to Geth
      proposed_blocks = GethDriver.propose_block(
        transactions: ethscription_txs,
        new_ethscriptions_block: ethscriptions_block,
        head_block: l2_genesis_block,
        safe_block: l2_genesis_block,
        finalized_block: l2_genesis_block
      )
      
      expect(proposed_blocks).not_to be_empty
      
      final_block = proposed_blocks.last
      puts "\nSuccessfully proposed L2 block:"
      puts "  Number: #{final_block.number}"
      puts "  Hash: #{final_block.block_hash}"
      puts "  Timestamp: #{final_block.timestamp}"
      puts "  Transactions: #{final_block.ethscription_transactions.length}"
      
      # Verify the block was actually created in Geth
      l2_block = EthRpcClient.l2.get_block(final_block.number)
      expect(l2_block).not_to be_nil
      expect(l2_block['hash']).to eq(final_block.block_hash.to_hex)
      
      puts "\n✅ Successfully imported mainnet block #{l1_genesis_block_number} as L2 block #{final_block.number}"
    end
  end
end