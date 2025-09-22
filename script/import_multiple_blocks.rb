#!/usr/bin/env ruby

# Script to import multiple blocks and show progress
# Usage: ruby script/import_multiple_blocks.rb [num_blocks]

require_relative '../config/environment'
require 'dotenv'

# Load environment
Dotenv.load('.env.development')

num_blocks = (ARGV[0] || 10).to_i

puts "=" * 80
puts "Importing #{num_blocks} L1 blocks using EthBlockImporter"
puts "=" * 80

# Initialize the importer
importer = EthBlockImporter.new

# Track stats
total_ethscriptions = 0
blocks_with_ethscriptions = []

num_blocks.times do |i|
  next_block = importer.next_block_to_import
  
  print "\n[#{i+1}/#{num_blocks}] Importing L1 block #{next_block}... "
  
  begin
    ethscriptions_blocks, eth_blocks = importer.import_next_block
    
    if ethscriptions_blocks.any?
      final_block = ethscriptions_blocks.last
      num_txs = final_block.ethscription_transactions.length
      
      # Subtract 1 for the L1 attributes transaction to get actual Ethscriptions
      num_ethscriptions = num_txs - 1
      
      if num_ethscriptions > 0
        print "✅ Found #{num_ethscriptions} Ethscription(s)!"
        total_ethscriptions += num_ethscriptions
        blocks_with_ethscriptions << {
          l1_block: eth_blocks.first.number,
          l2_block: final_block.number,
          count: num_ethscriptions
        }
      else
        print "✅ No Ethscriptions (only L1 attributes tx)"
      end
    else
      print "❌ No blocks imported"
    end
    
  rescue => e
    print "❌ Error: #{e.message}"
    puts "\n#{e.backtrace.first(3).join("\n")}"
    break
  end
end

# Summary
puts "\n\n" + "=" * 80
puts "SUMMARY"
puts "=" * 80
puts "Total Ethscriptions found: #{total_ethscriptions}"
puts "Blocks with Ethscriptions: #{blocks_with_ethscriptions.length}"

if blocks_with_ethscriptions.any?
  puts "\nBlocks containing Ethscriptions:"
  blocks_with_ethscriptions.each do |block_info|
    puts "  L1 block #{block_info[:l1_block]} → L2 block #{block_info[:l2_block]}: #{block_info[:count]} Ethscription(s)"
  end
end

# Check final L2 state
l2_block_num = `curl -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' http://localhost:8545 | jq -r '.result'`.strip
puts "\nFinal L2 block number: #{l2_block_num.to_i(16)}"