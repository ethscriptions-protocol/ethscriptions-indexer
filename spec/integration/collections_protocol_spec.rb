require 'rails_helper'

RSpec.describe "Collections Protocol", type: :integration do
  include EthscriptionsTestHelper

  let(:alice) { valid_address("alice") }
  let(:bob) { valid_address("bob") }
  let(:charlie) { valid_address("charlie") }
  # Ethscriptions are created by sending to any address with data in the input
  # The protocol handler is called automatically by the Ethscriptions contract
  let(:dummy_recipient) { valid_address("recipient") }
  let(:zero_merkle_root) { '0x' + '0' * 64 }

  describe "Collection Creation" do
    it "creates a collection with metadata fields" do
      collection_data = {
        "p" => "erc-721-ethscriptions-collection",
        "op" => "create_collection",
        "name" => "Test NFTs",
        "symbol" => "TEST",
        "description" => "Test collection",
        "max_supply" => "10000",
        "logo_image_uri" => "https://example.com/logo.png",
        "merkle_root" => zero_merkle_root
      }

      expect_ethscription_success(
        create_input(
          creator: alice,
          to: dummy_recipient,
          data_uri: "data:," + collection_data.to_json
        )
      ) do |results|
        # Verify the ethscription was created
        ethscription_id = results[:ethscription_ids].first
        stored = get_ethscription_content(ethscription_id)

        content_str = stored[:content]
        json_payload = content_str.start_with?('data:,') ? content_str.sub(/\Adata:,/, '') : content_str
        parsed = begin
          JSON.parse(json_payload)
        rescue JSON::ParserError
          raise RSpec::Expectations::ExpectationNotMetError, "Stored content not valid JSON: #{json_payload.inspect}"
        end

        expect(parsed['p']).to eq('erc-721-ethscriptions-collection')
        expect(parsed['op']).to eq('create_collection')
        expect(parsed['name']).to eq('Test NFTs')

        # TODO: Once contract is deployed, verify collection was created in contract storage
      end
    end

    it "creates a minimal collection with only required fields" do
      collection_data = {
        "p" => "erc-721-ethscriptions-collection",
        "op" => "create_collection",
        "name" => "Minimal Collection",
        "symbol" => "MIN",
        "max_supply" => "1000",
        "merkle_root" => zero_merkle_root
      }

      expect_ethscription_success(
        create_input(
          creator: alice,
          to: dummy_recipient,
          data_uri: "data:," + collection_data.to_json
        )
      )
    end

    it "handles numeric strings for max_supply (JS compatibility)" do
      collection_data = {
        "p" => "erc-721-ethscriptions-collection",
        "op" => "create_collection",
        "name" => "Big Supply Collection",
        "symbol" => "BIG",
        "max_supply" => "1000000000000000000", # Large number as string
        "merkle_root" => zero_merkle_root
      }

      expect_ethscription_success(
        create_input(
          creator: alice,
          to: dummy_recipient,
          data_uri: "data:," + collection_data.to_json
        )
      )
    end
  end

  describe "Collection Items" do
    let(:collection_id) { "0x1234567890123456789012345678901234567890" }

    it "creates an item with NFT attributes" do
      item_data = {
        "p" => "erc-721-ethscriptions-collection",
        "op" => "create_item",
        "collection_id" => collection_id,
        "name" => "Item #1",
        "description" => "First item in the collection",
        "image_uri" => "https://example.com/item1.png",
        "attributes" => [
          {"trait_type" => "Color", "value" => "Blue"},
          {"trait_type" => "Rarity", "value" => "Common"},
          {"trait_type" => "Level", "value" => "5"}
        ]
      }

      expect_ethscription_success(
        create_input(
          creator: alice,
          to: dummy_recipient,
          data_uri: "data:," + item_data.to_json
        )
      )
    end

    it "creates an item with camelCase attribute keys" do
      item_data = {
        "p" => "erc-721-ethscriptions-collection",
        "op" => "create_item",
        "collection_id" => collection_id,
        "name" => "Item #2",
        "attributes" => [
          {"trait_type" =>"Size", "value" => "Large"},
          {"trait_type" =>"Speed", "value" => "Fast"}
        ]
      }

      expect_ethscription_success(
        create_input(
          creator: alice,
          to: dummy_recipient,
          data_uri: "data:," + item_data.to_json
        )
      )
    end

    it "edits an item to clear attributes using type hint" do
      # Clear attributes by providing empty array with type hint
      edit_data = {
        "p" => "erc-721-ethscriptions-collection",
        "op" => "edit_item",
        "collection_id" => collection_id,
        "item_index" =>0,
        "name" => "Updated Item",
        "attributes" => ["(string,string)[]", []] # Type hint for empty attribute array
      }

      expect_ethscription_success(
        create_input(
          creator: alice,
          to: dummy_recipient,
          data_uri: "data:," + edit_data.to_json
        )
      )
    end

    it "edits an item to update attributes" do
      edit_data = {
        "p" => "erc-721-ethscriptions-collection",
        "op" => "edit_item",
        "collection_id" => collection_id,
        "item_index" =>0,
        "attributes" => [
          {"trait_type" => "Color", "value" => "Red"},
          {"trait_type" => "Status", "value" => "Upgraded"}
        ]
      }

      expect_ethscription_success(
        create_input(
          creator: alice,
          to: dummy_recipient,
          data_uri: "data:," + edit_data.to_json
        )
      )
    end
  end

  describe "Collection Management" do
    let(:collection_id) { "0x1234567890123456789012345678901234567890" }

    it "locks a collection" do
      lock_data = {
        "p" => "erc-721-ethscriptions-collection",
        "op" => "lock_collection",
        "collection_id" => collection_id
      }

      expect_ethscription_success(
        create_input(
          creator: alice,
          to: dummy_recipient,
          data_uri: "data:," + lock_data.to_json
        )
      )
    end

    it "transfers collection ownership explicitly" do
      collection_data = {
        "p" => "erc-721-ethscriptions-collection",
        "op" => "create_collection",
        "name" => "Ownership Test",
        "symbol" => "OWN",
        "max_supply" => "10",
        "description" => "",
        "logo_image_uri" => "",
        "banner_image_uri" => "",
        "background_color" => "",
        "website_link" => "",
        "twitter_link" => "",
        "discord_link" => "",
        "merkle_root" => zero_merkle_root
      }

      creation = expect_ethscription_success(
        create_input(
          creator: alice,
          to: alice,
          data_uri: "data:," + collection_data.to_json
        )
      )

      created_collection_id = creation[:ethscription_ids].first
      initial_owner = CollectionsReader.get_collection_owner(created_collection_id)
      expect(initial_owner.downcase).to eq(alice.downcase)

      transfer_data = {
        "p" => "erc-721-ethscriptions-collection",
        "op" => "transfer_ownership",
        "collection_id" => created_collection_id,
        "new_owner" => bob
      }

      expect_ethscription_success(
        create_input(
          creator: alice,
          to: alice,
          data_uri: "data:," + transfer_data.to_json
        )
      )

      updated_owner = CollectionsReader.get_collection_owner(created_collection_id)
      expect(updated_owner.downcase).to eq(bob.downcase)
    end

    it "keeps ownership unchanged when the collection leader ethscription transfers" do
      collection_data = {
        "p" => "erc-721-ethscriptions-collection",
        "op" => "create_collection",
        "name" => "Leader Transfer",
        "symbol" => "LEAD",
        "max_supply" => "5",
        "description" => "",
        "logo_image_uri" => "",
        "banner_image_uri" => "",
        "background_color" => "",
        "website_link" => "",
        "twitter_link" => "",
        "discord_link" => "",
        "merkle_root" => zero_merkle_root
      }

      creation = expect_ethscription_success(
        create_input(
          creator: alice,
          to: alice,
          data_uri: "data:," + collection_data.to_json
        )
      )

      created_collection_id = creation[:ethscription_ids].first
      expect(CollectionsReader.get_collection_owner(created_collection_id).downcase).to eq(alice.downcase)

      expect_transfer_success(
        transfer_input(from: alice, to: bob, id: created_collection_id),
        created_collection_id,
        bob
      )

      # Collection owner stays Alice despite the ethscription transfer
      current_owner = CollectionsReader.get_collection_owner(created_collection_id)
      expect(current_owner.downcase).to eq(alice.downcase)
    end

    it "renounces ownership even when locked" do
      collection_data = {
        "p" => "erc-721-ethscriptions-collection",
        "op" => "create_collection",
        "name" => "Renounce Test",
        "symbol" => "REN",
        "max_supply" => "25",
        "description" => "",
        "logo_image_uri" => "",
        "banner_image_uri" => "",
        "background_color" => "",
        "website_link" => "",
        "twitter_link" => "",
        "discord_link" => "",
        "merkle_root" => zero_merkle_root
      }

      creation = expect_ethscription_success(
        create_input(
          creator: alice,
          to: alice,
          data_uri: "data:," + collection_data.to_json
        )
      )

      created_collection_id = creation[:ethscription_ids].first

      lock_data = {
        "p" => "erc-721-ethscriptions-collection",
        "op" => "lock_collection",
        "collection_id" => created_collection_id
      }

      expect_ethscription_success(
        create_input(
          creator: alice,
          to: alice,
          data_uri: "data:," + lock_data.to_json
        )
      )

      renounce_data = {
        "p" => "erc-721-ethscriptions-collection",
        "op" => "renounce_ownership",
        "collection_id" => created_collection_id
      }

      expect_ethscription_success(
        create_input(
          creator: alice,
          to: alice,
          data_uri: "data:," + renounce_data.to_json
        )
      )

      owner_after_renounce = CollectionsReader.get_collection_owner(created_collection_id)
      expect(owner_after_renounce.downcase).to eq('0x0000000000000000000000000000000000000000')
    end

    it "handles batch operations with arrays" do
      batch_data = {
        "p" => "erc-721-ethscriptions-collection",
        "op" => "batch_create_items",
        "collection_id" => collection_id,
        "items" => [
          {
            "name" => "Item #1",
            "attributes" => [
              {"trait_type" => "Type", "value" => "Common"}
            ]
          },
          {
            "name" => "Item #2",
            "attributes" => [
              {"trait_type" => "Type", "value" => "Rare"}
            ]
          }
        ]
      }

      expect_ethscription_success(
        create_input(
          creator: alice,
          to: dummy_recipient,
          data_uri: "data:," + batch_data.to_json
        )
      )
    end
  end

  describe "Type Inference" do
    it "correctly infers mixed field types" do
      mixed_data = {
        "p" => "erc-721-ethscriptions-collection",
        "op" => "complex_operation",
        "item_id" => "12345", # String number -> uint256
        "active" => true, # JSON boolean -> bool
        "owner" => "0xabcdef1234567890123456789012345678901234", # Address
        "data" => "0x" + "a" * 64, # bytes32
        "tags" => ["tag1", "tag2", "tag3"], # string[]
        "amounts" => ["100", "200", "300"], # uint256[]
        "description" => "Regular string" # string
      }

      expect_ethscription_success(
        create_input(
          creator: alice,
          to: dummy_recipient,
          data_uri: "data:," + mixed_data.to_json
        )
      )
    end

    it "preserves JSON field order for struct compatibility" do
      # Fields must be in exact order to match Solidity struct
      struct_data = {
        "p" => "erc-721-ethscriptions-collection",
        "op" => "structured_op",
        "field1" => "first",
        "field2" => "second",
        "field3" => "third"
      }

      expect_ethscription_success(
        create_input(
          creator: alice,
          to: dummy_recipient,
          data_uri: "data:," + struct_data.to_json
        )
      ) do |results|
        # The protocol parser should preserve field order
        # TODO: Once contract is deployed, verify struct was decoded correctly
      end
    end
  end

  describe "Contract State Verification" do
    it "creates a collection and verifies it exists in contract" do
      # Must include ALL CollectionParams fields in correct order
      collection_data = {
        "p" => "erc-721-ethscriptions-collection",
        "op" => "create_collection",
        "name" => "Verified Collection",
        "symbol" => "VRFY",
        "max_supply" => "100",
        "description" => "",
        "logo_image_uri" => "",
        "banner_image_uri" => "",
        "background_color" => "",
        "website_link" => "",
        "twitter_link" => "",
        "discord_link" => "",
        "merkle_root" => zero_merkle_root
      }
      
      expect_ethscription_success(
        create_input(
          creator: alice,
          to: dummy_recipient,
          data_uri: "data:," + collection_data.to_json
        )
      ) do |results|
        collection_id = results[:ethscription_ids].first

        # Verify collection exists in contract
        expect(collection_exists?(collection_id)).to eq(true), "Collection should exist in contract"

        # Verify collection state
        state = get_collection_state(collection_id)
        expect(state).to be_present
        expect(state[:collectionContract]).not_to eq('0x0000000000000000000000000000000000000000')

        expect(state[:createTxHash]).to eq(collection_id)
        expect(state[:currentSize]).to eq(0)
        expect(state[:locked]).to eq(false)

        # Verify collection metadata
        metadata = get_collection_metadata(collection_id)
        expect(metadata).to be_present
        expect(metadata[:name]).to eq("Verified Collection")
        expect(metadata[:symbol]).to eq("VRFY")
        expect(metadata[:totalSupply]).to eq(100)
      end
    end

    it "invalid protocol data creates ethscription but doesn't affect collections" do
      # First, count how many collections exist
      # initial_collection_count = get_total_collections()

      # Send data with number too large for uint256
      too_big = "115792089237316195423570985008687907853269984665640564039457584007913129639936"
      invalid_data = {
        "p" => "erc-721-ethscriptions-collection",
        "op" => "create_collection",
        "name" => "Invalid",
        "max_supply" => too_big
      }

      expect_protocol_extraction_failure(
        create_input(
          creator: alice,
          to: dummy_recipient,
          data_uri: "data:," + invalid_data.to_json
        )
      ) do |results, stored|
        # Ethscription created and content stored
        expect(stored[:content]).to include('"p":"erc-721-ethscriptions-collection"')

        # TODO: Verify collection count didn't increase
        # final_collection_count = get_total_collections()
        # expect(final_collection_count).to eq(initial_collection_count)
      end
    end

    it "malformed JSON creates ethscription but doesn't affect collections" do
      expect_protocol_extraction_failure(
        create_input(
          creator: alice,
          to: dummy_recipient,
          data_uri: "data:,{\"p\":\"collections\",\"op\":\"create\",broken}"
        )
      ) do |results, stored|
        # TODO: Verify no collection was created
        # final_collection_count = get_total_collections()
        # expect(final_collection_count).to eq(initial_collection_count)
      end
    end
  end

  describe "End-to-End Collection Workflow" do
    it "creates collection, adds items, edits items, and locks collection" do
      # Step 1: Create collection
      create_data = {
        "p" => "erc-721-ethscriptions-collection",
        "op" => "create_collection",
        "name" => "Full Test Collection",
        "symbol" => "FULL",
        "max_supply" => "10"
      }

      create_results = expect_ethscription_success(
        create_input(
          creator: alice,
          to: dummy_recipient,
          data_uri: "data:," + create_data.to_json
        )
      )

      collection_id = create_results[:ethscription_ids].first

      # TODO: Verify collection exists
      # collection_info = get_collection_info(collection_id)
      # expect(collection_info[:currentSize]).to eq(0)
      # expect(collection_info[:locked]).to eq(false)

      # Step 2: Add an item
      item_data = {
        "p" => "erc-721-ethscriptions-collection",
        "op" => "create_item",
        "collection_id" => collection_id,
        "name" => "Item 1",
        "attributes" => [
          {"trait_type" => "Color", "value" => "Blue"}
        ]
      }

      expect_ethscription_success(
        create_input(
          creator: alice,
          to: dummy_recipient,
          data_uri: "data:," + item_data.to_json
        )
      )

      # TODO: Verify item exists
      # collection_info = get_collection_info(collection_id)
      # expect(collection_info[:currentSize]).to eq(1)
      # item = get_collection_item(collection_id, 0)
      # expect(item[:name]).to eq("Item 1")
      # expect(item[:attributes].length).to eq(1)

      # Step 3: Edit item to clear attributes
      edit_data = {
        "p" => "erc-721-ethscriptions-collection",
        "op" => "edit_item",
        "collection_id" => collection_id,
        "item_index" =>0,
        "name" => "Updated Item",
        "attributes" => ["(string,string)[]", []] # Type hint for empty array
      }

      expect_ethscription_success(
        create_input(
          creator: alice,
          to: dummy_recipient,
          data_uri: "data:," + edit_data.to_json
        )
      )

      # TODO: Verify item was updated
      # item = get_collection_item(collection_id, 0)
      # expect(item[:name]).to eq("Updated Item")
      # expect(item[:attributes]).to be_empty

      # Step 4: Lock collection
      lock_data = {
        "p" => "erc-721-ethscriptions-collection",
        "op" => "lock_collection",
        "collection_id" => collection_id
      }

      expect_ethscription_success(
        create_input(
          creator: alice,
          to: dummy_recipient,
          data_uri: "data:," + lock_data.to_json
        )
      )

      # TODO: Verify collection is locked
      # collection_info = get_collection_info(collection_id)
      # expect(collection_info[:locked]).to eq(true)
    end
  end

  describe "Multi-line JSON Support" do
    it "accepts properly formatted multi-line JSON" do
      # ProtocolParser now parses JSON instead of using regex
      # so multi-line JSON should work
      multiline_json = {
        "p" => "erc-721-ethscriptions-collection",
        "op" => "create_collection",
        "name" => "Multi-line Test",
        "description" => "This JSON
spans multiple
lines for readability"
      }.to_json

      expect_ethscription_success(
        create_input(
          creator: alice,
          to: dummy_recipient,
          data_uri: "data:," + multiline_json
        )
      )
    end
  end

  describe "Boolean String Handling" do
    it "treats string 'true' and 'false' as strings, not booleans" do
      string_bool_data = {
        "p" => "erc-721-ethscriptions-collection",
        "op" => "test_bools",
        "stringTrue" => "true", # Should remain string
        "stringFalse" => "false", # Should remain string
        "realTrue" => true, # JSON boolean
        "realFalse" => false # JSON boolean
      }

      expect_ethscription_success(
        create_input(
          creator: alice,
          to: dummy_recipient,
          data_uri: "data:," + string_bool_data.to_json
        )
      ) do |results|
        # TODO: Once contract is deployed, verify correct type handling
        # stringTrue/stringFalse should be strings
        # realTrue/realFalse should be booleans
      end
    end
  end
end
