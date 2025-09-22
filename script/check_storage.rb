#!/usr/bin/env ruby
require_relative '../config/environment'

tx_hash = ARGV[0] || '0x05aac415994e0e01e66c4970133a51a4cdcea1f3a967743b87e6eb08f2f4d9f9'

puts "Checking storage for ethscription: #{tx_hash}"
puts

# Get from storage
stored = StorageReader.get_ethscription(tx_hash)

if stored
  puts "Storage data:"
  puts "  Creator: #{stored[:creator]}"
  puts "  Initial Owner: #{stored[:initial_owner]}"
  puts "  L1 Block Number: #{stored[:l1_block_number]}"
  puts "  L2 Block Number: #{stored[:l2_block_number]}"
  puts "  Created At: #{stored[:created_at]} (#{Time.at(stored[:created_at])})" if stored[:created_at]
  puts "  Mimetype: #{stored[:mimetype]}"
  puts "  Content SHA: #{stored[:content_sha]}"

  # Check owner
  owner = StorageReader.get_owner(tx_hash)
  puts "  Current Owner: #{owner}"
else
  puts "Not found in storage"
end

puts
puts "Checking L2 events..."

# Get the L2 block receipts
l2_block = EthRpcClient.l2.call('eth_getBlockByNumber', ['0x1', true])
if l2_block && l2_block['transactions'].any?
  puts "L2 Block 1 has #{l2_block['transactions'].size} transactions"

  # Get receipts
  receipts = EthRpcClient.l2.call('eth_getBlockReceipts', [l2_block['hash']])
  decoded = EventDecoder.decode_block_receipts(receipts)

  puts "Found #{decoded[:creations].size} creations"
  decoded[:creations].each do |creation|
    puts "  - #{creation[:tx_hash]} by #{creation[:creator]} to #{creation[:initial_owner]}"
  end

  puts "Found #{decoded[:transfers].size} transfers"
  decoded[:transfers].each do |transfer|
    puts "  - Token #{transfer[:token_id]}: #{transfer[:from]} -> #{transfer[:to]}"
  end
end