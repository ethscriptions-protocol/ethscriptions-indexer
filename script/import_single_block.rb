#!/usr/bin/env ruby

# Simple script to import a single block using the existing EthBlockImporter
# Usage: ruby script/import_single_block.rb

require_relative '../config/environment'
require 'dotenv'

# Load environment
Dotenv.load('.env.development')

puts "=" * 80
puts "Importing next L1 block using EthBlockImporter"
puts "=" * 80

# Initialize the importer
importer = EthBlockImporter.new

# Get current state
current_l2_max = importer.current_max_ethscriptions_block_number
current_l1_max = importer.current_max_eth_block_number
next_block = importer.next_block_to_import

puts "\nCurrent state:"
puts "  L2 max block: #{current_l2_max}"
puts "  L1 max block: #{current_l1_max}" 
puts "  Next L1 block to import: #{next_block}"

# Import the next block
puts "\n🚀 Importing L1 block #{next_block}..."

begin
  ethscriptions_blocks, eth_blocks = importer.import_next_block
  
  if ethscriptions_blocks.any?
    final_block = ethscriptions_blocks.last
    puts "\n✅ Successfully imported:"
    puts "  L1 block: #{eth_blocks.first.number}"
    puts "  L2 blocks created: #{ethscriptions_blocks.length}"
    puts "  Final L2 block number: #{final_block.number}"
    puts "  Transactions: #{final_block.ethscription_transactions.length}"
  else
    puts "❌ No blocks were imported"
  end
  
rescue => e
  puts "❌ Error importing block: #{e.message}"
  puts e.backtrace.first(5).join("\n")
  exit 1
end

puts "\n" + "=" * 80
puts "Import complete!"
puts "=" * 80