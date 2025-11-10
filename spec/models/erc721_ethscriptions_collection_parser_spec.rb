require 'rails_helper'

RSpec.describe Erc721EthscriptionsCollectionParser do
  describe 'via ProtocolParser' do
    let(:default_params) { [''.b, ''.b, ''.b] }
    let(:zero_merkle_root) { '0x' + '0' * 64 }

    describe 'validation rules' do
      # @generic-compatible
      it 'requires data:, prefix' do
        json = '{"p":"erc-721-ethscriptions-collection","op":"lock_collection","collection_id":"0x' + 'a' * 64 + '"}'
        result = ProtocolParser.for_calldata(json)
        expect(result).to eq(default_params)
      end

      # @generic-compatible
      it 'requires valid JSON' do
        result = ProtocolParser.for_calldata('data:,{invalid json}')
        expect(result).to eq(default_params)
      end

      it 'requires p:erc-721-ethscriptions-collection' do
        json = 'data:,{"p":"other","op":"lock_collection","collection_id":"0x' + 'a' * 64 + '"}'
        result = ProtocolParser.for_calldata(json)
        expect(result).to eq(default_params)
      end

      it 'requires known operation' do
        json = 'data:,{"p":"erc-721-ethscriptions-collection","op":"unknown_op","collection_id":"0x' + 'a' * 64 + '"}'
        result = ProtocolParser.for_calldata(json)
        expect(result).to eq(default_params)
      end

      # @generic-compatible
      it 'enforces exact key order with p and op first' do
        # Wrong order - op before p
        json1 = 'data:,{"op":"lock_collection","p":"erc-721-ethscriptions-collection","collection_id":"0x' + 'a' * 64 + '"}'
        expect(ProtocolParser.for_calldata(json1)).to eq(default_params)

        # Wrong order - collection_id before op
        json2 = 'data:,{"p":"erc-721-ethscriptions-collection","collection_id":"0x' + 'a' * 64 + '","op":"lock_collection"}'
        expect(ProtocolParser.for_calldata(json2)).to eq(default_params)

        # Correct order
        json3 = 'data:,{"p":"erc-721-ethscriptions-collection","op":"lock_collection","collection_id":"0x' + 'a' * 64 + '"}'
        result = ProtocolParser.for_calldata(json3)
        expect(result[0]).to eq('erc-721-ethscriptions-collection'.b)
        expect(result[1]).to eq('lock_collection'.b)
      end

      # @generic-compatible
      it 'rejects extra keys' do
        json = 'data:,{"p":"erc-721-ethscriptions-collection","op":"lock_collection","collection_id":"0x' + 'a' * 64 + '","extra":"field"}'
        result = ProtocolParser.for_calldata(json)
        expect(result).to eq(default_params)
      end

      # @generic-compatible
      it 'validates uint256 format - no leading zeros' do
        # Valid
      valid_json = %(data:,{"p":"erc-721-ethscriptions-collection","op":"create_collection","name":"Test","symbol":"TEST","max_supply":"1000","description":"","logo_image_uri":"","banner_image_uri":"","background_color":"","website_link":"","twitter_link":"","discord_link":"","merkle_root":"#{zero_merkle_root}"})
        result = ProtocolParser.for_calldata(valid_json)
        expect(result[0]).to eq('erc-721-ethscriptions-collection'.b)

        # Invalid - leading zero
      invalid_json = %(data:,{"p":"erc-721-ethscriptions-collection","op":"create_collection","name":"Test","symbol":"TEST","max_supply":"01000","description":"","logo_image_uri":"","banner_image_uri":"","background_color":"","website_link":"","twitter_link":"","discord_link":"","merkle_root":"#{zero_merkle_root}"})
        result = ProtocolParser.for_calldata(invalid_json)
        expect(result).to eq(default_params)
      end

      # @generic-compatible
      it 'validates bytes32 format - lowercase hex only' do
        # Valid lowercase
        valid_json = 'data:,{"p":"erc-721-ethscriptions-collection","op":"lock_collection","collection_id":"0x' + 'a' * 64 + '"}'
        result = ProtocolParser.for_calldata(valid_json)
        expect(result[0]).to eq('erc-721-ethscriptions-collection'.b)

        # Invalid - uppercase
        invalid_json = 'data:,{"p":"erc-721-ethscriptions-collection","op":"lock_collection","collection_id":"0x' + 'A' * 64 + '"}'
        result = ProtocolParser.for_calldata(invalid_json)
        expect(result).to eq(default_params)

        # Invalid - wrong length
        invalid_json2 = 'data:,{"p":"erc-721-ethscriptions-collection","op":"lock_collection","collection_id":"0x' + 'a' * 63 + '"}'
        result = ProtocolParser.for_calldata(invalid_json2)
        expect(result).to eq(default_params)

        # Invalid - no 0x prefix
        invalid_json3 = 'data:,{"p":"erc-721-ethscriptions-collection","op":"lock_collection","collection_id":"' + 'a' * 64 + '"}'
        result = ProtocolParser.for_calldata(invalid_json3)
        expect(result).to eq(default_params)
      end
    end

    describe 'create_collection operation' do
      let(:valid_create_json) do
        %(data:,{"p":"erc-721-ethscriptions-collection","op":"create_collection","name":"My Collection","symbol":"MYC","max_supply":"10000","description":"A test collection","logo_image_uri":"esc://logo","banner_image_uri":"esc://banner","background_color":"#FF5733","website_link":"https://example.com","twitter_link":"https://twitter.com/test","discord_link":"https://discord.gg/test","merkle_root":"#{zero_merkle_root}"})
      end

      it 'encodes create_collection correctly' do
        result = ProtocolParser.for_calldata(valid_create_json)

        expect(result[0]).to eq('erc-721-ethscriptions-collection'.b)
        expect(result[1]).to eq('create_collection'.b)

        # Decode and verify
        decoded = Eth::Abi.decode(
          ['(string,string,uint256,string,string,string,string,string,string,string,bytes32)'],
          result[2]
        )[0]

        expect(decoded[0]).to eq("My Collection")
        expect(decoded[1]).to eq("MYC")
        expect(decoded[2]).to eq(10000)
        expect(decoded[3]).to eq("A test collection")
        expect(decoded[4]).to eq("esc://logo")
        expect(decoded[5]).to eq("esc://banner")
        expect(decoded[6]).to eq("#FF5733")
        expect(decoded[7]).to eq("https://example.com")
        expect(decoded[8]).to eq("https://twitter.com/test")
        expect(decoded[9]).to eq("https://discord.gg/test")
        expect(decoded[10]).to eq([zero_merkle_root[2..]].pack('H*'))
      end

      it 'handles empty optional fields' do
        json = %(data:,{"p":"erc-721-ethscriptions-collection","op":"create_collection","name":"Test","symbol":"TST","max_supply":"100","description":"","logo_image_uri":"","banner_image_uri":"","background_color":"","website_link":"","twitter_link":"","discord_link":"","merkle_root":"#{zero_merkle_root}"})
        result = ProtocolParser.for_calldata(json)

        expect(result[0]).to eq('erc-721-ethscriptions-collection'.b)
        expect(result[1]).to eq('create_collection'.b)

        decoded = Eth::Abi.decode(
          ['(string,string,uint256,string,string,string,string,string,string,string,bytes32)'],
          result[2]
        )[0]

        expect(decoded[0]).to eq("Test")
        expect(decoded[1]).to eq("TST")
        expect(decoded[2]).to eq(100)
        expect(decoded[3]).to eq("")
        expect(decoded[10]).to eq([zero_merkle_root[2..]].pack('H*'))
      end

      it 'rejects uint256 values that exceed maximum' do
        # Value that exceeds uint256 max
        too_large = (2**256).to_s  # One more than max

        json = %(data:,{"p":"erc-721-ethscriptions-collection","op":"create_collection","name":"Test","symbol":"TST","max_supply":"#{too_large}","description":"","logo_image_uri":"","banner_image_uri":"","background_color":"","website_link":"","twitter_link":"","discord_link":"","merkle_root":"#{zero_merkle_root}"})
        result = ProtocolParser.for_calldata(json)

        # Should return default params due to validation failure
        expect(result).to eq(default_params)
      end

      it 'accepts maximum valid uint256 value' do
        # Maximum valid uint256
        max_uint256 = (2**256 - 1).to_s

        json = %(data:,{"p":"erc-721-ethscriptions-collection","op":"create_collection","name":"Test","symbol":"TST","max_supply":"#{max_uint256}","description":"","logo_image_uri":"","banner_image_uri":"","background_color":"","website_link":"","twitter_link":"","discord_link":"","merkle_root":"#{zero_merkle_root}"})
        result = ProtocolParser.for_calldata(json)

        # Should succeed with max value
        expect(result[0]).to eq('erc-721-ethscriptions-collection'.b)
        expect(result[1]).to eq('create_collection'.b)

        decoded = Eth::Abi.decode(
          ['(string,string,uint256,string,string,string,string,string,string,string,bytes32)'],
          result[2]
        )[0]

        expect(decoded[2]).to eq(2**256 - 1)
        expect(decoded[10]).to eq([zero_merkle_root[2..]].pack('H*'))
      end
    end

    describe 'add_self_to_collection operation' do
      let(:collection_id_hex) { '0x' + '1' * 64 }
      let(:current_item_id) { '0x' + 'a' * 64 }

      it 'encodes add_self_to_collection correctly' do
        json = 'data:,{"p":"erc-721-ethscriptions-collection","op":"add_self_to_collection","collection_id":"' + collection_id_hex + '","item":{"item_index":"0","name":"Item 1","background_color":"#FF0000","description":"First item","attributes":[{"trait_type":"Rarity","value":"Common"},{"trait_type":"Level","value":"1"}],"merkle_proof":[]}}'

        result = ProtocolParser.for_calldata(json)

        expect(result[0]).to eq('erc-721-ethscriptions-collection'.b)
        expect(result[1]).to eq('add_self_to_collection'.b)

        decoded = Eth::Abi.decode(
          ['(bytes32,(bytes32,uint256,string,string,string,(string,string)[],bytes32[]))'],
          result[2]
        )[0]

        expect(decoded[0].unpack1('H*')).to eq(collection_id_hex[2..])

        item = decoded[1]
        # Note: Item structure now has contentHash as first field
        expect(item[1]).to eq(0) # item_index
        expect(item[2]).to eq('Item 1') # name
        expect(item[3]).to eq('#FF0000') # background_color
        expect(item[4]).to eq('First item') # description
        expect(item[5]).to eq([["Rarity", "Common"], ["Level", "1"]]) # attributes
        expect(item[6]).to eq([]) # merkle_proof
      end

      it 'validates attribute key order' do
        # Wrong key order in attributes (value before trait_type)
        json = 'data:,{"p":"erc-721-ethscriptions-collection","op":"add_self_to_collection","collection_id":"' + collection_id_hex + '","item":{"item_index":"0","name":"Item 1","background_color":"#FF0000","description":"First item","attributes":[{"value":"Common","trait_type":"Rarity"}],"merkle_proof":[]}}'
        result = ProtocolParser.for_calldata(json)
        expect(result).to eq(default_params)
      end

      it 'handles empty attributes array' do
        json = 'data:,{"p":"erc-721-ethscriptions-collection","op":"add_self_to_collection","collection_id":"' + collection_id_hex + '","item":{"item_index":"0","name":"Item 1","background_color":"","description":"","attributes":[],"merkle_proof":[]}}'
        result = ProtocolParser.for_calldata(json)

        expect(result[0]).to eq('erc-721-ethscriptions-collection'.b)

        decoded = Eth::Abi.decode(
          ['(bytes32,(bytes32,uint256,string,string,string,(string,string)[],bytes32[]))'],
          result[2]
        )[0]

        item = decoded[1]
        expect(item[5]).to eq([]) # Empty attributes
        expect(item[6]).to eq([]) # Empty merkle_proof
      end
    end

    describe 'remove_items operation' do
      it 'encodes remove_items correctly' do
        json = 'data:,{"p":"erc-721-ethscriptions-collection","op":"remove_items","collection_id":"0x' + '1' * 64 + '","ethscription_ids":["0x' + '2' * 64 + '","0x' + '3' * 64 + '"]}'
        result = ProtocolParser.for_calldata(json)

        expect(result[0]).to eq('erc-721-ethscriptions-collection'.b)
        expect(result[1]).to eq('remove_items'.b)

        decoded = Eth::Abi.decode(['(bytes32,bytes32[])'], result[2])[0]

        expect(decoded[0].unpack1('H*')).to eq('1' * 64)
        expect(decoded[1][0].unpack1('H*')).to eq('2' * 64)
        expect(decoded[1][1].unpack1('H*')).to eq('3' * 64)
      end
    end

    describe 'edit_collection operation' do
      it 'encodes edit_collection correctly' do
        json = %(data:,{"p":"erc-721-ethscriptions-collection","op":"edit_collection","collection_id":"0x#{"1" * 64}","description":"Updated","logo_image_uri":"new_logo","banner_image_uri":"","background_color":"#00FF00","website_link":"https://new.com","twitter_link":"","discord_link":"","merkle_root":"#{zero_merkle_root}"})
        result = ProtocolParser.for_calldata(json)

        expect(result[0]).to eq('erc-721-ethscriptions-collection'.b)
        expect(result[1]).to eq('edit_collection'.b)

        decoded = Eth::Abi.decode(
          ['(bytes32,string,string,string,string,string,string,string,bytes32)'],
          result[2]
        )[0]

        expect(decoded[0].unpack1('H*')).to eq('1' * 64)
        expect(decoded[1]).to eq("Updated")
        expect(decoded[2]).to eq("new_logo")
        expect(decoded[3]).to eq("")
        expect(decoded[4]).to eq("#00FF00")
        expect(decoded[5]).to eq("https://new.com")
        expect(decoded[8]).to eq([zero_merkle_root[2..]].pack('H*'))
      end
    end

    describe 'edit_collection_item operation' do
      it 'encodes edit_collection_item correctly' do
        json = 'data:,{"p":"erc-721-ethscriptions-collection","op":"edit_collection_item","collection_id":"0x' + '1' * 64 + '","item_index":"5","name":"Updated Name","background_color":"#0000FF","description":"Updated desc","attributes":[{"trait_type":"New","value":"Value"}]}'
        result = ProtocolParser.for_calldata(json)

        expect(result[0]).to eq('erc-721-ethscriptions-collection'.b)
        expect(result[1]).to eq('edit_collection_item'.b)

        decoded = Eth::Abi.decode(
          ['(bytes32,uint256,string,string,string,(string,string)[])'],
          result[2]
        )[0]

        expect(decoded[0].unpack1('H*')).to eq('1' * 64)
        expect(decoded[1]).to eq(5)
        expect(decoded[2]).to eq("Updated Name")
        expect(decoded[3]).to eq("#0000FF")
        expect(decoded[4]).to eq("Updated desc")
        expect(decoded[5]).to eq([["New", "Value"]])
      end
    end

    describe 'lock_collection operation' do
      it 'encodes lock_collection as single bytes32' do
        json = 'data:,{"p":"erc-721-ethscriptions-collection","op":"lock_collection","collection_id":"0x' + '1' * 64 + '"}'
        result = ProtocolParser.for_calldata(json)

        expect(result[0]).to eq('erc-721-ethscriptions-collection'.b)
        expect(result[1]).to eq('lock_collection'.b)

        # Single bytes32, not a tuple
        decoded = Eth::Abi.decode(['bytes32'], result[2])[0]
        expect(decoded.unpack1('H*')).to eq('1' * 64)
      end
    end

    describe 'round-trip tests' do
      # @generic-compatible
      it 'preserves all data through encode/decode cycle' do
        test_cases = [
          {
            json: %(data:,{"p":"erc-721-ethscriptions-collection","op":"create_collection","name":"Test","symbol":"TST","max_supply":"100","description":"Desc","logo_image_uri":"logo","banner_image_uri":"banner","background_color":"#FFF","website_link":"http://test","twitter_link":"@test","discord_link":"discord","merkle_root":"#{zero_merkle_root}"}),
            abi_type: '(string,string,uint256,string,string,string,string,string,string,string,bytes32)',
            expected: ["Test", "TST", 100, "Desc", "logo", "banner", "#FFF", "http://test", "@test", "discord", [zero_merkle_root[2..]].pack('H*')]
          },
          {
            json: 'data:,{"p":"erc-721-ethscriptions-collection","op":"lock_collection","collection_id":"0x' + 'a' * 64 + '"}',
            abi_type: 'bytes32',
            expected: ['a' * 64].pack('H*')
          }
        ]

        test_cases.each do |test_case|
          result = ProtocolParser.for_calldata(test_case[:json])
          expect(result[0]).not_to eq(''.b)

          decoded = Eth::Abi.decode([test_case[:abi_type]], result[2])

          if test_case[:abi_type].start_with?('(')
            # Tuple
            expect(decoded[0]).to eq(test_case[:expected])
          else
            # Single value
            expect(decoded[0]).to eq(test_case[:expected])
          end
        end
      end
    end

    describe 'error cases' do
      it 'returns default params for malformed JSON' do
        test_cases = [
          'data:,{broken json',
          'data:,',
          # Note: 'data:,null' is a valid word-domains registration for the word "null"
          # so it's excluded from this test
          'data:,[]',
          'data:,"string"'
        ]

        test_cases.each do |json|
          result = ProtocolParser.for_calldata(json)
          expect(result).to eq(default_params)
        end
      end

      it 'rejects null values in string fields (no silent coercion)' do
        # Test null in create_collection string fields
        json_with_null = %(data:,{"p":"erc-721-ethscriptions-collection","op":"create_collection","name":null,"symbol":"TEST","max_supply":"100","description":"","logo_image_uri":"","banner_image_uri":"","background_color":"","website_link":"","twitter_link":"","discord_link":"","merkle_root":"#{zero_merkle_root}"})
        result = ProtocolParser.for_calldata(json_with_null)
        expect(result).to eq(default_params)

        # Test null in description field
        json_with_null_desc = %(data:,{"p":"erc-721-ethscriptions-collection","op":"create_collection","name":"Test","symbol":"TEST","max_supply":"100","description":null,"logo_image_uri":"","banner_image_uri":"","background_color":"","website_link":"","twitter_link":"","discord_link":"","merkle_root":"#{zero_merkle_root}"})
        result = ProtocolParser.for_calldata(json_with_null_desc)
        expect(result).to eq(default_params)

        # Test null in item fields
        json_with_null_item = 'data:,{"p":"erc-721-ethscriptions-collection","op":"add_items_batch","collection_id":"0x' + '1' * 64 + '","items":[{"item_index":"0","name":null,"ethscription_id":"0x' + '2' * 64 + '","background_color":"","description":"","attributes":[]}]}'
        result = ProtocolParser.for_calldata(json_with_null_item)
        expect(result).to eq(default_params)

        # Test null in attribute fields
        json_with_null_attr = 'data:,{"p":"erc-721-ethscriptions-collection","op":"add_items_batch","collection_id":"0x' + '1' * 64 + '","items":[{"item_index":"0","name":"Item","ethscription_id":"0x' + '2' * 64 + '","background_color":"","description":"","attributes":[{"trait_type":null,"value":"test"}]}]}'
        result = ProtocolParser.for_calldata(json_with_null_attr)
        expect(result).to eq(default_params)
      end

      it 'returns default params for missing required fields' do
        # Missing collection_id
        json = 'data:,{"p":"erc-721-ethscriptions-collection","op":"lock_collection"}'
        result = ProtocolParser.for_calldata(json)
        expect(result).to eq(default_params)
      end
    end
  end
end