#!/usr/bin/env ruby

# This script is called by Foundry tests via FFI to test Ruby compression logic
# It receives content as an argument and returns JSON with compression results

require 'json'
require 'fastlz'

def compress_if_beneficial(data)
  compressed = FastLZ.compress(data)
  
  if FastLZ.decompress(compressed) != data
    raise "Compression failed"
  end
  
  ratio = compressed.bytesize.to_f / data.bytesize.to_f
  
  puts ratio
  
  # Only use compressed if it's at least 10% smaller
  if compressed.bytesize < (data.bytesize * Rational(9, 10))
    [compressed, true]
  else
    [data, false]
  end
end

# Get content from command line argument
content = ARGV[0]

if content.nil? || content.empty?
  result = {
    compressed: "0x",
    is_compressed: false,
    original_size: 0,
    compressed_size: 0
  }
else
  # Duplicate the string to make it mutable, keep original encoding
  mutable_content = content.dup
  
  compressed_data, is_compressed = compress_if_beneficial(mutable_content)
  
  result = {
    # Convert to hex for Solidity (prefix with 0x)
    compressed: "0x" + compressed_data.unpack1('H*'),
    is_compressed: is_compressed,
    original_size: content.bytesize,
    compressed_size: compressed_data.bytesize
  }
end

# Output JSON for Foundry to parse
puts result.to_json