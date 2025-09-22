#!/usr/bin/env ruby

require 'json'
require_relative 'app/models/token_params_extractor'

# Test token parameter extraction with regex-first validation
class TestTokenValidationRegex

  def self.run_tests
    puts "Testing Token Parameter Extraction (Regex-first)\n" + "="*40

    tests = [
      # Valid cases - exact format required
      {
        name: "Valid deploy",
        input: 'data:,{"p":"erc-20","op":"deploy","tick":"punk","max":"1000","lim":"100"}',
        expected: ["deploy".b, "erc-20".b, "punk".b, 1000, 100, 0]
      },
      {
        name: "Valid mint",
        input: 'data:,{"p":"erc-20","op":"mint","tick":"punk","id":"1","amt":"100"}',
        expected: ["mint".b, "erc-20".b, "punk".b, 1, 0, 100]
      },
      {
        name: "Valid with zero values",
        input: 'data:,{"p":"erc-20","op":"mint","tick":"punk","id":"0","amt":"0"}',
        expected: ["mint".b, "erc-20".b, "punk".b, 0, 0, 0]
      },
      {
        name: "Valid with max length tick (28 chars)",
        input: 'data:,{"p":"erc-20","op":"mint","tick":"abcdefghijklmnopqrstuvwxyz12","id":"1","amt":"100"}',
        expected: ["mint".b, "erc-20".b, "abcdefghijklmnopqrstuvwxyz12".b, 1, 0, 100]
      },

      # Invalid - wrong format/structure
      {
        name: "Mint missing id field",
        input: 'data:,{"p":"erc-20","op":"mint","tick":"punk","amt":"100"}',
        expected: TokenParamsExtractor::DEFAULT_PARAMS
      },
      {
        name: "Mint missing amt field",
        input: 'data:,{"p":"erc-20","op":"mint","tick":"punk","id":"1"}',
        expected: TokenParamsExtractor::DEFAULT_PARAMS
      },
      {
        name: "Deploy missing lim",
        input: 'data:,{"p":"erc-20","op":"deploy","tick":"punk","max":"1000"}',
        expected: TokenParamsExtractor::DEFAULT_PARAMS
      },
      {
        name: "Extra spaces in JSON",
        input: 'data:,{"p": "erc-20","op": "mint","tick": "punk","id": "1","amt": "100"}',
        expected: TokenParamsExtractor::DEFAULT_PARAMS
      },
      {
        name: "Wrong key order",
        input: 'data:,{"op":"mint","p":"erc-20","tick":"punk","id":"1","amt":"100"}',
        expected: TokenParamsExtractor::DEFAULT_PARAMS
      },
      {
        name: "Extra field",
        input: 'data:,{"p":"erc-20","op":"mint","tick":"punk","id":"1","amt":"100","extra":"bad"}',
        expected: TokenParamsExtractor::DEFAULT_PARAMS
      },
      {
        name: "Integer values instead of strings",
        input: 'data:,{"p":"erc-20","op":"mint","tick":"punk","id":1,"amt":100}',
        expected: TokenParamsExtractor::DEFAULT_PARAMS
      },
      {
        name: "Leading zeros",
        input: 'data:,{"p":"erc-20","op":"mint","tick":"punk","id":"01","amt":"100"}',
        expected: TokenParamsExtractor::DEFAULT_PARAMS
      },
      {
        name: "Hex number",
        input: 'data:,{"p":"erc-20","op":"mint","tick":"punk","id":"0x10","amt":"100"}',
        expected: TokenParamsExtractor::DEFAULT_PARAMS
      },
      {
        name: "Negative number",
        input: 'data:,{"p":"erc-20","op":"mint","tick":"punk","id":"-1","amt":"100"}',
        expected: TokenParamsExtractor::DEFAULT_PARAMS
      },
      {
        name: "Float number",
        input: 'data:,{"p":"erc-20","op":"mint","tick":"punk","id":"1.5","amt":"100"}',
        expected: TokenParamsExtractor::DEFAULT_PARAMS
      },
      {
        name: "Array in id field",
        input: 'data:,{"p":"erc-20","op":"mint","tick":"punk","id":[1,2],"amt":"100"}',
        expected: TokenParamsExtractor::DEFAULT_PARAMS
      },
      {
        name: "Nested JSON object",
        input: 'data:,{"p":"erc-20","op":"mint","tick":"punk","id":"1","amt":"100","meta":{"foo":"bar"}}',
        expected: TokenParamsExtractor::DEFAULT_PARAMS
      },
      {
        name: "Protocol with underscore",
        input: 'data:,{"p":"erc_20","op":"mint","tick":"punk","id":"1","amt":"100"}',
        expected: TokenParamsExtractor::DEFAULT_PARAMS
      },
      {
        name: "Protocol with uppercase",
        input: 'data:,{"p":"ERC-20","op":"mint","tick":"punk","id":"1","amt":"100"}',
        expected: TokenParamsExtractor::DEFAULT_PARAMS
      },
      {
        name: "Tick with uppercase (invalid)",
        input: 'data:,{"p":"erc-20","op":"mint","tick":"PUNK","id":"1","amt":"100"}',
        expected: TokenParamsExtractor::DEFAULT_PARAMS
      },
      {
        name: "Tick with emoji (invalid)",
        input: 'data:,{"p":"erc-20","op":"mint","tick":"🚀moon","id":"1","amt":"100"}',
        expected: TokenParamsExtractor::DEFAULT_PARAMS
      },
      {
        name: "Tick with hyphen (invalid)",
        input: 'data:,{"p":"erc-20","op":"mint","tick":"pu-nk","id":"1","amt":"100"}',
        expected: TokenParamsExtractor::DEFAULT_PARAMS
      },
      {
        name: "Tick too long (29 chars)",
        input: 'data:,{"p":"erc-20","op":"mint","tick":"abcdefghijklmnopqrstuvwxyz123","id":"1","amt":"100"}',
        expected: TokenParamsExtractor::DEFAULT_PARAMS
      },
      {
        name: "SQL injection in tick",
        input: 'data:,{"p":"erc-20","op":"mint","tick":"punk\nDROP TABLE","id":"1","amt":"100"}',
        expected: TokenParamsExtractor::DEFAULT_PARAMS
      },
      {
        name: "Number too large for uint256",
        input: 'data:,{"p":"erc-20","op":"mint","tick":"punk","id":"1","amt":"' + (TokenParamsExtractor::UINT256_MAX + 1).to_s + '"}',
        expected: TokenParamsExtractor::DEFAULT_PARAMS
      },
      {
        name: "Not a data URI",
        input: 'https://example.com',
        expected: TokenParamsExtractor::DEFAULT_PARAMS
      },
      {
        name: "Nil input",
        input: nil,
        expected: TokenParamsExtractor::DEFAULT_PARAMS
      }
    ]

    passed = 0
    failed = 0

    tests.each do |test|
      result = TokenParamsExtractor.extract(test[:input])
      success = result == test[:expected]

      if success
        passed += 1
        puts "✅ #{test[:name]}"
      else
        failed += 1
        puts "❌ #{test[:name]}"
        puts "   Input:    #{test[:input].inspect}"
        puts "   Expected: #{test[:expected].inspect}"
        puts "   Got:      #{result.inspect}"
      end
    end

    puts "\n" + "="*40
    puts "Results: #{passed} passed, #{failed} failed"
    puts "SUCCESS!" if failed == 0
  end
end

# Run the tests
TestTokenValidationRegex.run_tests