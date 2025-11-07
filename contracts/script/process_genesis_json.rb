#!/usr/bin/env ruby

require 'json'
require 'digest'
require 'base64'

# Read the existing genesis JSON file
json_path = File.join(File.dirname(__FILE__), 'genesisEthscriptions.json')
data = JSON.parse(File.read(json_path))

# Process each ethscription
data['ethscriptions'].each do |ethscription|
  content_uri = ethscription['content_uri']

  # Calculate content URI hash (as hex string with 0x prefix for JSON)
  content_uri_sha = '0x' + Digest::SHA256.hexdigest(content_uri)
  ethscription['content_uri_sha'] = content_uri_sha

  # Parse the data URI
  if content_uri.start_with?('data:')
    # Remove 'data:' prefix
    uri_without_prefix = content_uri[5..-1]

    # Find the comma that separates metadata from data
    comma_index = uri_without_prefix.index(',')

    if comma_index
      metadata = uri_without_prefix[0...comma_index]
      data_part = uri_without_prefix[(comma_index + 1)..-1]

      # Check if it's base64 encoded
      is_base64 = metadata.include?(';base64')

      # Get the content
      if is_base64
        # Decode from base64 for storage
        content = Base64.decode64(data_part)
        # Store as hex string for JSON (with 0x prefix)
        ethscription['content'] = '0x' + content.unpack1('H*')
      else
        # For non-base64, keep the original encoded form (preserves percent-encoding)
        # Store as hex string for JSON (with 0x prefix)
        ethscription['content'] = '0x' + data_part.unpack('H*')[0]
      end
    else
      # Invalid data URI format, store empty content
      ethscription['content'] = '0x'
    end
  else
    # Not a data URI, store the whole thing as content
    ethscription['content'] = '0x' + content_uri.unpack('H*')[0]
  end
end

# Write the updated JSON back
File.write(json_path, JSON.pretty_generate(data))

puts "Processed #{data['ethscriptions'].length} ethscriptions"
puts "Added content_uri_sha and content fields"