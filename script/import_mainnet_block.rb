#!/usr/bin/env ruby

# Script to import a single mainnet block for testing
# Usage: ruby script/import_mainnet_block.rb

require_relative '../config/environment'
require 'dotenv'

# Load mainnet configuration
Dotenv.load('.env.mainnet')

def import_mainnet_genesis_block
  l1_genesis_block_number = ENV.fetch('L1_GENESIS_BLOCK').to_i
  
  puts "=" * 80
  puts "Importing L1 genesis block #{l1_genesis_block_number} from mainnet"
  puts "=" * 80
  
  # Get the actual L2 genesis block from Geth
  puts "\n📋 Fetching L2 genesis block from Geth..."
  l2_genesis = EthRpcClient.l2.get_block(0)
  
  if l2_genesis.nil?
    puts "❌ Failed to fetch L2 genesis block. Make sure Geth is initialized with genesis."
    exit 1
  end
  
  puts "✅ L2 Genesis block found: #{l2_genesis['hash']}"
  
  # Initialize L2 genesis block with actual hash from Geth
  l2_genesis_block = EthscriptionsBlock.new(
    number: 0,
    block_hash: Hash32.from_hex(l2_genesis['hash']),
    parent_hash: Hash32.from_hex(l2_genesis['parentHash'] || '0x' + '0' * 64),
    timestamp: l2_genesis['timestamp'].to_i(16),
    eth_block_number: l1_genesis_block_number,
    eth_block_timestamp: nil,
    sequence_number: 0
  )
  
  # Fetch the L1 block with full transaction details
  puts "\n📦 Fetching L1 block #{l1_genesis_block_number}..."
  l1_block_data = EthRpcClient.l1.get_block(l1_genesis_block_number, true)
  
  if l1_block_data.nil?
    puts "❌ Failed to fetch L1 block"
    exit 1
  end
  
  l1_eth_block = EthBlock.from_rpc_result(l1_block_data)
  
  puts "✅ L1 Block fetched:"
  puts "   Hash: #{l1_eth_block.block_hash.to_hex}"
  puts "   Timestamp: #{Time.at(l1_eth_block.timestamp)}"
  puts "   Transactions: #{l1_block_data['transactions'].length}"
  
  # Create Ethscriptions block
  ethscriptions_block = EthscriptionsBlock.from_eth_block(l1_eth_block)
  
  # Get block receipts
  puts "\n📋 Fetching block receipts..."
  receipts = EthRpcClient.l1.get_block_receipts(l1_genesis_block_number)
  
  # Parse Ethscription transactions
  puts "\n🔍 Parsing Ethscription transactions..."
  ethscription_txs = EthTransaction.ethscription_txs_from_rpc_results(
    l1_block_data,
    receipts,
    ethscriptions_block
  )
  
  puts "✅ Found #{ethscription_txs.length} Ethscription transactions"
  
  if ethscription_txs.any?
    ethscription_txs.each_with_index do |tx, i|
      if tx.respond_to?(:ethscription_data) && tx.ethscription_data
        puts "   #{i+1}. #{tx.ethscription_data[:operation] || 'unknown'}"
        if tx.ethscription_data[:mimetype]
          puts "      Mimetype: #{tx.ethscription_data[:mimetype]}"
        end
      end
    end
  end
  
  # Propose block to Geth
  puts "\n🚀 Proposing block to Geth L2..."
  
  begin
    proposed_blocks = GethDriver.propose_block(
      transactions: ethscription_txs,
      new_ethscriptions_block: ethscriptions_block,
      head_block: l2_genesis_block,
      safe_block: l2_genesis_block,
      finalized_block: l2_genesis_block
    )
    
    if proposed_blocks.empty?
      puts "❌ No blocks were proposed"
      exit 1
    end
    
    final_block = proposed_blocks.last
    puts "✅ Successfully proposed L2 block:"
    puts "   Number: #{final_block.number}"
    puts "   Hash: #{final_block.block_hash}"
    puts "   Timestamp: #{Time.at(final_block.timestamp)}"
    puts "   Transactions: #{final_block.ethscription_transactions.length}"
    
    # Verify in Geth
    puts "\n🔎 Verifying block in Geth..."
    l2_block = EthRpcClient.l2.get_block(final_block.number)
    
    if l2_block && l2_block['hash'] == final_block.block_hash.to_hex
      puts "✅ Block verified in Geth!"
      puts "\n" + "=" * 80
      puts "SUCCESS: Imported mainnet block #{l1_genesis_block_number} as L2 block #{final_block.number}"
      puts "=" * 80
    else
      puts "❌ Block verification failed"
      exit 1
    end
    
  rescue => e
    puts "❌ Error proposing block: #{e.message}"
    puts e.backtrace.first(5).join("\n")
    exit 1
  end
end

# Check if Geth is running
begin
  EthRpcClient.l2.call("eth_blockNumber")
rescue => e
  puts "❌ Geth L2 is not running or not accessible"
  puts "   Make sure to start Geth first with the proper configuration"
  puts "   Error: #{e.message}"
  exit 1
end

# Check L1 connection
begin
  EthRpcClient.l1.call("eth_blockNumber")
rescue => e
  puts "❌ Cannot connect to L1 RPC"
  puts "   Check your ETH_RPC_URL environment variable"
  puts "   Error: #{e.message}"
  exit 1
end

# Run the import
import_mainnet_genesis_block