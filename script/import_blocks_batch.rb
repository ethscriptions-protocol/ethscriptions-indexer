#!/usr/bin/env ruby

require_relative '../config/environment'

target_block = ARGV[0]&.to_i || 17480873

importer = EthBlockImporter.new

# Get current max block
current_max = importer.current_max_eth_block_number
puts "Current max block: #{current_max}"
puts "Target block: #{target_block}"
puts "Blocks to import: #{target_block - current_max}"

if current_max >= target_block
  puts "Already at or past target block"
  exit 0
end

total_imported = 0
ethscriptions_found = 0
start_time = Time.now

while importer.current_max_eth_block_number < target_block
  current_block = importer.current_max_eth_block_number + 1

  begin
    # Import the next block
    ethscriptions_blocks, eth_blocks = importer.import_next_block

    # Check if any Ethscriptions were created
    if ethscriptions_blocks && ethscriptions_blocks.any?
      ethscriptions_blocks.each do |eb|
        if eb.ethscription_transactions.any?
          created_count = eb.ethscription_transactions.length
          puts "\nBlock #{current_block}: Created #{created_count} Ethscriptions!"
          ethscriptions_found += created_count
        end
      end
    elsif current_block % 10 == 0
      print "."
      print " #{current_block}" if current_block % 100 == 0
    end

    total_imported += 1

    # Progress update every 100 blocks
    if total_imported % 100 == 0
      elapsed = Time.now - start_time
      blocks_per_second = total_imported / elapsed
      remaining = target_block - importer.current_max_eth_block_number
      eta = remaining / blocks_per_second

      puts "\nProgress: Block #{importer.current_max_eth_block_number}/#{target_block}"
      puts "Speed: #{blocks_per_second.round(2)} blocks/sec"
      puts "ETA: #{(eta/60).round(1)} minutes"
      puts "Ethscriptions found: #{ethscriptions_found}"
    end

  rescue => e
    puts "\nError importing block #{current_block}: #{e.message}"
    puts e.backtrace.first(5)
    exit 1
  end
end

puts "\n" + "="*60
puts "Import complete!"
puts "Total blocks imported: #{total_imported}"
puts "Total Ethscriptions created: #{ethscriptions_found}"
puts "Time taken: #{((Time.now - start_time)/60).round(2)} minutes"

# Show validation summary if enabled
if ENV['VALIDATE_IMPORT'] == 'true'
  puts "\n" + "="*60
  puts importer.validation_summary
  puts "="*60
end

# Run verification if we found any Ethscriptions
if ethscriptions_found > 0 && ENV['RUN_JS_VERIFICATION'] == 'true'
  puts "\nRunning JS verification..."
  system("node script/verify_ethscriptions.js")
end