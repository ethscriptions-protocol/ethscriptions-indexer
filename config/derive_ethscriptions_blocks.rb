require 'clockwork'
require './config/boot'
require './config/environment'
require 'active_support/time'
require 'optparse'

# Define required arguments, descriptions, and defaults
REQUIRED_CONFIG = {
  'L1_NETWORK' => { description: 'L1 network (e.g., mainnet, sepolia)', required: true },
  'GETH_RPC_URL' => { description: 'Geth Engine API RPC URL (with JWT auth)', required: true },
  'NON_AUTH_GETH_RPC_URL' => { description: 'Geth HTTP RPC URL (no auth)', required: true },
  'L1_RPC_URL' => { description: 'L1 RPC URL for fetching blocks', required: true },
  'JWT_SECRET' => { description: 'JWT Secret for Engine API', required: true },
  'L1_GENESIS_BLOCK' => { description: 'L1 Genesis Block number', required: true },
  'L1_PREFETCH_THREADS' => { description: 'L1 prefetch thread count', default: '2' },
  'VALIDATION_ENABLED' => { description: 'Enable validation (true/false)', default: 'false' },
  'JOB_CONCURRENCY' => { description: 'SolidQueue worker processes', default: '2' },
  'IMPORT_INTERVAL' => { description: 'Seconds between import attempts', default: '6' }
}

# Parse command line options
options = {}
parser = OptionParser.new do |opts|
  opts.banner = "Usage: clockwork derive_ethscriptions_blocks.rb [options]"

  REQUIRED_CONFIG.each do |key, config|
    flag = "--#{key.downcase.tr('_', '-')}"
    opts.on("#{flag} VALUE", config[:description]) do |v|
      options[key] = v
    end
  end

  opts.on("-h", "--help", "Show this help message") do
    puts opts
    puts "\nEnvironment variables can also be used for any option."
    puts "\nExample:"
    puts "  L1_NETWORK=mainnet L1_RPC_URL=https://eth.llamarpc.com GETH_RPC_URL=http://localhost:9545 \\"
    puts "    NON_AUTH_GETH_RPC_URL=http://localhost:8545 JWT_SECRET=/tmp/jwtsecret \\"
    puts "    L1_GENESIS_BLOCK=17478951 VALIDATION_ENABLED=true \\"
    puts "    bundle exec clockwork config/derive_ethscriptions_blocks.rb"
    exit
  end
end

parser.parse!

# Merge ENV vars with command line options and defaults
config = REQUIRED_CONFIG.each_with_object({}) do |(key, config_opts), hash|
  hash[key] = options[key] || ENV[key] || config_opts[:default]
end

# Check for missing required values
missing = config.select do |key, value|
  REQUIRED_CONFIG[key][:required] && (value.nil? || value.empty?)
end

if missing.any?
  puts "Missing required configuration:"
  missing.each do |key, _|
    puts "  #{key}: #{REQUIRED_CONFIG[key][:description]}"
    puts "    Set via environment variable: #{key}=value"
    puts "    Or via command line: --#{key.downcase.tr('_', '-')} value"
  end

  puts "\nExample usage:"
  puts "  L1_NETWORK=mainnet L1_RPC_URL=https://eth.llamarpc.com GETH_RPC_URL=http://localhost:9545 \\"
  puts "    NON_AUTH_GETH_RPC_URL=http://localhost:8545 JWT_SECRET=/tmp/jwtsecret \\"
  puts "    L1_GENESIS_BLOCK=17478951 \\"
  puts "    bundle exec clockwork config/derive_ethscriptions_blocks.rb"
  exit 1
end

# Set final values in ENV
config.each { |key, value| ENV[key] = value }

# Display configuration
puts "="*80
puts "Starting Ethscriptions Block Importer"
puts "="*80
puts "Configuration:"
puts "  L1 Network: #{ENV['L1_NETWORK']}"
puts "  L1 Genesis Block: #{ENV['L1_GENESIS_BLOCK']}"
puts "  L1 RPC: #{ENV['L1_RPC_URL'][0..30]}..."
puts "  Geth RPC: #{ENV['NON_AUTH_GETH_RPC_URL']}"
puts "  L1 Prefetch Threads: #{ENV['L1_PREFETCH_THREADS']}"
puts "  Job Concurrency: #{ENV['JOB_CONCURRENCY']}"
puts "  Validation: #{ENV.fetch('VALIDATION_ENABLED').casecmp?('true') ? 'ENABLED' : 'disabled'}"
puts "  Import Interval: #{ENV['IMPORT_INTERVAL']}s"
puts "="*80

module Clockwork
  handler do |job|
    puts "\n[#{Time.now}] Running #{job}"
  end

  error_handler do |error|
    report_exception_every = 15.minutes

    exception_key = ["clockwork-ethscriptions", error.class, error.message, error.backtrace[0]]

    last_reported_at = Rails.cache.read(exception_key)

    if last_reported_at.blank? || (Time.zone.now - last_reported_at > report_exception_every)
      Rails.logger.error "Clockwork error: #{error.class} - #{error.message}"
      Rails.logger.error error.backtrace.first(10).join("\n")

      # Report to Airbrake if configured
      Airbrake.notify(error) if defined?(Airbrake)

      Rails.cache.write(exception_key, Time.zone.now)
    end
  end

  import_interval = ENV.fetch('IMPORT_INTERVAL', '6').to_i

  every(import_interval.seconds, 'import_ethscriptions_blocks') do
    importer = EthBlockImporter.new

    # Track statistics
    total_blocks_imported = 0
    start_time = Time.now

    begin
      loop do
        begin
          initial_block = importer.current_max_eth_block_number

          # Import blocks
          importer.import_blocks_until_done

          final_block = importer.current_max_eth_block_number
          blocks_imported = final_block - initial_block

          if blocks_imported > 0
            total_blocks_imported += blocks_imported

            puts "[#{Time.now}] Imported #{blocks_imported} blocks (#{initial_block + 1} to #{final_block})"
          else
            # We're caught up
            elapsed = (Time.now - start_time).round(2)

            if total_blocks_imported > 0
              puts "[#{Time.now}] Session summary: Imported #{total_blocks_imported} blocks in #{elapsed}s"

              # Reset counters
              total_blocks_imported = 0
              start_time = Time.now
            end

            puts "[#{Time.now}] Caught up at block #{final_block}. Waiting #{import_interval}s..."
          end

        rescue EthBlockImporter::BlockNotReadyToImportError => e
          # This is normal when caught up
          current = importer.current_max_eth_block_number
          puts "[#{Time.now}] Waiting for new blocks (current: #{current})..."

        rescue EthBlockImporter::ReorgDetectedError => e
          Rails.logger.warn "[#{Time.now}] ⚠️  Reorg detected! Reinitializing importer..."
          puts "[#{Time.now}] ⚠️  Reorg detected at block #{importer.current_max_eth_block_number}"

          # Reinitialize importer to handle reorg
          importer.shutdown
          importer = EthBlockImporter.new
          puts "[#{Time.now}] Importer reinitialized. Continuing from block #{importer.current_max_eth_block_number}"

        rescue EthBlockImporter::ValidationFailureError => e
          Rails.logger.fatal "[#{Time.now}] 🛑 VALIDATION FAILURE: #{e.message}"
          puts "[#{Time.now}] 🛑 VALIDATION FAILURE - System stopping for investigation"
          puts "[#{Time.now}] Fix the validation issue and restart manually"
          exit 1

        rescue EthBlockImporter::ValidationStalledError => e
          Rails.logger.info "[#{Time.now}] ⏸️  VALIDATION BEHIND: #{e.message}"
          puts "[#{Time.now}] ⏸️  Validation is behind - waiting #{import_interval}s for validation to catch up..."
          # Don't sleep here - the loop's sleep at line 192 will handle it
        rescue => e
          Rails.logger.error "Import error: #{e.class} - #{e.message}"
          Rails.logger.error e.backtrace.join("\n")

          puts "[#{Time.now}] ❌ Error: #{e.message}"

          # For other errors, wait and retry
          puts "[#{Time.now}] Retrying in #{import_interval}s..."
        end

        sleep import_interval
      end
    ensure
      importer&.shutdown
    end
  end
end
