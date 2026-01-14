require 'clockwork'
require './config/boot'
require './config/environment'
require 'active_support/time'

# Ensure prefetcher shuts down cleanly on process exit
at_exit do
  puts "Shutting down prefetcher..."
  EthBlock.reset_prefetcher!
rescue => e
  puts "Error shutting down prefetcher: #{e.message}"
end

module Clockwork
  handler do |job|
    puts "Running #{job}"
  end

  error_handler do |error|
    report_exception_every = 15.minutes

    exception_key = ["clockwork-airbrake", error.class, error.message, error.backtrace[0]].to_cache_key

    last_reported_at = Rails.cache.read(exception_key)

    if last_reported_at.blank? || (Time.zone.now - last_reported_at > report_exception_every)
      Airbrake.notify(error)
      Rails.cache.write(exception_key, Time.zone.now)
    end
  end

  every(6.seconds, 'import_blocks_until_done') do
    EthBlock.import_blocks_until_done
  end
end
