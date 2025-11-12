require 'rails_helper'
require_relative '../../lib/protocol_event_reader'

RSpec.describe "Collections Protocol End-to-End", type: :integration do
  include EthscriptionsTestHelper

  let(:alice) { valid_address("alice") }
  let(:bob) { valid_address("bob") }
  let(:dummy_recipient) { valid_address("recipient") }
  let(:zero_merkle_root) { '0x' + '0' * 64 }

  # Helper method to create and validate ethscriptions using the same pattern as the first test
  def create_and_validate_ethscription(creator:, to:, data_uri:)
    tx_spec = create_input(
      creator: creator,
      to: to,
      data_uri: data_uri
    )

    # Enable ESIP-6 to allow duplicate content
    results = import_l1_block([tx_spec], esip_overrides: { esip6_is_enabled: true })

    # Check if ethscription was created
    ethscription_id = results[:ethscription_ids]&.first
    success = ethscription_id.present? && results[:l2_receipts]&.first&.fetch(:status, nil) == '0x1'

    # Parse protocol data
    protocol_extracted = false
    protocol = nil
    operation = nil

    begin
      protocol, operation, _encoded_data = ProtocolParser.for_calldata(data_uri)
      protocol_extracted = protocol.present? && operation.present?
    rescue => e
      # Protocol extraction failed
    end

    # Parse events if we have L2 receipts
    protocol_success = false
    protocol_event = nil
    protocol_error = nil
    items_added_count = nil

    if results[:l2_receipts].present?
      receipt = results[:l2_receipts].first
      require_relative '../../lib/protocol_event_reader'
      events = ProtocolEventReader.parse_receipt_events(receipt)

      events.each do |event|
        case event[:event]
        when 'ProtocolHandlerSuccess'
          protocol_success = true
        when 'ProtocolHandlerFailed'
          protocol_success = false
          protocol_error = event[:reason]
        when 'CollectionCreated'
          protocol_event = 'CollectionCreated'
        when 'ItemsAdded'
          protocol_event = 'ItemsAdded'
          items_added_count = event[:count]
        when 'CollectionEdited'
          protocol_event = 'CollectionEdited'
        end
      end
    end

    {
      success: success,
      ethscription_id: ethscription_id,
      protocol_extracted: protocol_extracted,
      protocol_success: protocol_success,
      protocol_event: protocol_event,
      protocol_error: protocol_error,
      items_added_count: items_added_count
    }
  end

  describe "Complete Collection Workflow with Protocol Validation" do
    let(:collection_id) { nil }

    it "creates collection and validates protocol execution" do
      # Use the simple, working pattern
      collection_data = {
        "p" => "erc-721-ethscriptions-collection",
        "op" => "create_collection",
        "name" => "Test NFT",
        "symbol" => "TNFT",
        "max_supply" => "100",
        "description" => "Test",
        "logo_image_uri" => "",
        "banner_image_uri" => "",
        "background_color" => "",
        "website_link" => "",
        "twitter_link" => "",
        "discord_link" => "",
        "merkle_root" => zero_merkle_root,
        "initial_owner" => alice
      }

      tx_spec = create_input(
        creator: alice,
        to: dummy_recipient,
        data_uri: "data:," + collection_data.to_json
      )

      results = import_l1_block([tx_spec])

      # Validate ethscription creation
      expect(results[:ethscription_ids]).not_to be_empty, "Should create ethscription"
      expect(results[:l2_receipts]).not_to be_empty, "Should have L2 receipt"
      expect(results[:l2_receipts].first[:status]).to eq('0x1'), "L2 transaction should succeed"

      collection_id = results[:ethscription_ids].first
      expect(collection_id).to be_present

      # Validate ethscription content stored correctly
      stored = get_ethscription_content(collection_id)
      json_str = stored[:content]
      json_str = json_str.sub(/\Adata:,/, '') if json_str.start_with?('data:,')
      parsed = begin
        JSON.parse(json_str)
      rescue JSON::ParserError
        raise RSpec::Expectations::ExpectationNotMetError, "Stored content not valid JSON: #{json_str.inspect}"
      end

      expect(parsed['p']).to eq('erc-721-ethscriptions-collection')
      expect(parsed['op']).to eq('create_collection')
      expect(parsed['name']).to eq('Test NFT')

      # Parse events to check protocol execution
      if results[:l2_receipts].first[:logs].any?
        require_relative '../../lib/protocol_event_reader'

        events = ProtocolEventReader.parse_receipt_events(results[:l2_receipts].first)

        # Check for protocol success
        protocol_success = events.any? { |e| e[:event] == 'ProtocolHandlerSuccess' }
        protocol_failed = events.any? { |e| e[:event] == 'ProtocolHandlerFailed' }

        # Fallback: treat presence of expected protocol events as success if no explicit success/failure was emitted
        if !protocol_success && !protocol_failed
          protocol_success = events.any? { |e| [
            'CollectionCreated', 'ItemsAdded', 'ItemsRemoved', 'CollectionEdited', 'CollectionLocked'
          ].include?(e[:event]) }
        end

        expect(protocol_success).to eq(true), "Protocol handler should succeed"

        # Check for collection created event
        collection_created = events.any? { |e| e[:event] == 'CollectionCreated' }
        expect(collection_created).to eq(true), "Should emit CollectionCreated event"
      else
        fail "No logs found in L2 receipt!"
      end

      # Validate collection state in contract storage
      collection_state = get_collection_state(collection_id)
      expect(collection_state).not_to be_nil, "Collection state should be available"
      # Check if collection exists by verifying the contract address is not zero
      expect(collection_state[:collectionContract]).not_to eq('0x0000000000000000000000000000000000000000'), "Collection not found in contract storage"
      expect(collection_state[:currentSize]).to eq(0), "Collection should start empty"
      expect(collection_state[:locked]).to eq(false), "Collection should not be locked initially"
    end
  end

  describe "Add Items Batch with Nested Attributes" do
    it "adds multiple items with attributes and validates execution" do
      # Use the same pattern as the first test which works
      collection_data = {
        "p" => "erc-721-ethscriptions-collection",
        "op" => "create_collection",
        "name" => "Test Batch Collection",
        "symbol" => "TBATCH",
        "max_supply" => "100",
        "description" => "Test batch collection",
        "logo_image_uri" => "",
        "banner_image_uri" => "",
        "background_color" => "",
        "website_link" => "",
        "twitter_link" => "",
        "discord_link" => "",
        "merkle_root" => zero_merkle_root,
        "initial_owner" => alice
      }

      # Create collection using the same pattern as the first test
      tx_spec = create_input(
        creator: alice,
        to: alice,
        data_uri: "data:," + collection_data.to_json
      )

      results = import_l1_block([tx_spec], esip_overrides: { esip6_is_enabled: true })

      # Validate collection creation
      expect(results[:ethscription_ids]).not_to be_empty, "Should create ethscription"
      expect(results[:l2_receipts]).not_to be_empty, "Should have L2 receipt"
      expect(results[:l2_receipts].first[:status]).to eq('0x1'), "L2 transaction should succeed"

      collection_id = results[:ethscription_ids].first
      expect(collection_id).to be_present

      # Now create the ethscriptions that add themselves to the collection
      # Item 1: Create ethscription with add_self_to_collection
      item1_data = {
        "p" => "erc-721-ethscriptions-collection",
        "op" => "add_self_to_collection",
        "collection_id" => collection_id,
        "item" => {
          "item_index" => "0",
          "name" => "Test Item #0",
          "background_color" => "#648595",
          "description" => "First test item with multiple attributes",
          "attributes" => [
            {"trait_type" => "Type", "value" => "Common"},
            {"trait_type" => "Color", "value" => "Blue"},
            {"trait_type" => "Rarity", "value" => "1"},
            {"trait_type" => "Power", "value" => "100"}
          ],
          "merkle_proof" => []
        }
      }

      item1_spec = create_input(
        creator: alice,
        to: alice,
        data_uri: "data:," + item1_data.to_json
      )

      item1_results = import_l1_block([item1_spec], esip_overrides: { esip6_is_enabled: true })
      item1_id = item1_results[:ethscription_ids].first
      expect(item1_id).to be_present, "Item 1 should be created"

      # Item 2: Create ethscription with add_self_to_collection
      item2_data = {
        "p" => "erc-721-ethscriptions-collection",
        "op" => "add_self_to_collection",
        "collection_id" => collection_id,
        "item" => {
          "item_index" => "1",
          "name" => "Test Item #1",
          "background_color" => "#FF5733",
          "description" => "Second test item with different attributes",
          "attributes" => [
            {"trait_type" => "Type", "value" => "Rare"},
            {"trait_type" => "Color", "value" => "Red"},
            {"trait_type" => "Rarity", "value" => "5"},
            {"trait_type" => "Power", "value" => "500"}
          ],
          "merkle_proof" => []
        }
      }

      item2_spec = create_input(
        creator: alice,
        to: alice,
        data_uri: "data:," + item2_data.to_json
      )

      item2_results = import_l1_block([item2_spec], esip_overrides: { esip6_is_enabled: true })
      item2_id = item2_results[:ethscription_ids].first
      expect(item2_id).to be_present, "Item 2 should be created"

      # Validate first item addition
      expect(item1_results[:ethscription_ids]).not_to be_empty, "Should create first item ethscription"
      expect(item1_results[:l2_receipts]).not_to be_empty, "Should have L2 receipt for item 1"

      # Parse events for item 1
      require_relative '../../lib/protocol_event_reader'
      item1_events = ProtocolEventReader.parse_receipt_events(item1_results[:l2_receipts].first)

      item1_added_event = item1_events.find { |e| e[:event] == 'ItemsAdded' }
      expect(item1_added_event).not_to be_nil, "Should emit ItemsAdded event for item 1"
      expect(item1_added_event[:count]).to eq(1), "Should add 1 item"

      # Validate second item addition
      expect(item2_results[:ethscription_ids]).not_to be_empty, "Should create second item ethscription"
      expect(item2_results[:l2_receipts]).not_to be_empty, "Should have L2 receipt for item 2"

      # Parse events for item 2
      item2_events = ProtocolEventReader.parse_receipt_events(item2_results[:l2_receipts].first)

      item2_added_event = item2_events.find { |e| e[:event] == 'ItemsAdded' }
      expect(item2_added_event).not_to be_nil, "Should emit ItemsAdded event for item 2"
      expect(item2_added_event[:count]).to eq(1), "Should add 1 item"

      # Check for protocol success for both items
      item1_success = item1_events.any? { |e| e[:event] == 'ProtocolHandlerSuccess' }
      expect(item1_success).to eq(true), "Protocol operation should succeed for item 1"

      item2_success = item2_events.any? { |e| e[:event] == 'ProtocolHandlerSuccess' }
      expect(item2_success).to eq(true), "Protocol operation should succeed for item 2"

      # Validate collection state updated
      collection_state = get_collection_state(collection_id)
      expect(collection_state[:currentSize]).to eq(2), "Collection size should be 2 after adding items"

      # Validate individual items
      item0 = get_collection_item(collection_id, 0)
      expect(item0[:name]).to eq("Test Item #0")
      expect(item0[:ethscriptionId]).to eq(item1_id)  # Use the actual ID from creation
      expect(item0[:backgroundColor]).to eq("#648595")
      expect(item0[:description]).to eq("First test item with multiple attributes")
      expect(item0[:attributes].length).to eq(4)
      expect(item0[:attributes][0]).to eq(["Type", "Common"])
      expect(item0[:attributes][1]).to eq(["Color", "Blue"])

      item1 = get_collection_item(collection_id, 1)
      expect(item1[:name]).to eq("Test Item #1")
      expect(item1[:ethscriptionId]).to eq(item2_id)  # Use the actual ID from creation
      expect(item1[:attributes].length).to eq(4)
      expect(item1[:attributes][0]).to eq(["Type", "Rare"])
    end
  end

  describe "Merkle Root Enforcement" do
    let(:owner_merkle_root) { '0x' + '1' * 64 }

    it "allows the collection owner to add an item without a proof when the root is set" do
      collection_data = {
        "p" => "erc-721-ethscriptions-collection",
        "op" => "create_collection",
        "name" => "Owner Only",
        "symbol" => "OWNR",
        "max_supply" => "10",
        "description" => "Testing owner bypass",
        "logo_image_uri" => "",
        "banner_image_uri" => "",
        "background_color" => "",
        "website_link" => "",
        "twitter_link" => "",
        "discord_link" => "",
        "merkle_root" => owner_merkle_root,
        "initial_owner" => alice
      }

      collection_spec = create_input(
        creator: alice,
        to: alice,
        data_uri: "data:," + JSON.generate(collection_data)
      )

      collection_results = import_l1_block([collection_spec], esip_overrides: { esip6_is_enabled: true })
      expect(collection_results[:ethscription_ids]).not_to be_empty
      collection_id = collection_results[:ethscription_ids].first

      owner_item = {
        "p" => "erc-721-ethscriptions-collection",
        "op" => "add_self_to_collection",
        "collection_id" => collection_id,
        "item" => {
          "item_index" => "0",
          "name" => "Owner Item #0",
          "background_color" => "#123456",
          "description" => "Inserted by the owner without a proof",
          "attributes" => [
            {"trait_type" => "Tier", "value" => "Owner"}
          ],
          "merkle_proof" => []
        }
      }

      owner_spec = create_input(
        creator: alice,
        to: alice,
        data_uri: "data:," + JSON.generate(owner_item)
      )

      owner_results = import_l1_block([owner_spec], esip_overrides: { esip6_is_enabled: true })
      expect(owner_results[:ethscription_ids]).not_to be_empty
      owner_item_id = owner_results[:ethscription_ids].first

      receipt = owner_results[:l2_receipts].first
      events = ProtocolEventReader.parse_receipt_events(receipt)
      expect(events.any? { |e| e[:event] == 'ProtocolHandlerFailed' }).to eq(false)
      expect(events.any? { |e| e[:event] == 'ProtocolHandlerSuccess' }).to eq(true)

      added_event = events.find { |e| e[:event] == 'ItemsAdded' }
      expect(added_event).not_to be_nil
      expect(added_event[:count]).to eq(1)

      stored_item = get_collection_item(collection_id, 0)
      expect(stored_item[:ethscriptionId]).to eq(owner_item_id)
      expect(stored_item[:name]).to eq("Owner Item #0")
    end

    it "updates the merkle root via edit_collection to allow a non-owner add" do
      initial_merkle_root = zero_merkle_root
      collection_data = {
        "p" => "erc-721-ethscriptions-collection",
        "op" => "create_collection",
        "name" => "Editable Root",
        "symbol" => "EDIT",
        "max_supply" => "10",
        "description" => "Testing merkle root edits",
        "logo_image_uri" => "",
        "banner_image_uri" => "",
        "background_color" => "",
        "website_link" => "",
        "twitter_link" => "",
        "discord_link" => "",
        "merkle_root" => initial_merkle_root,
        "initial_owner" => alice
      }

      collection_spec = create_input(
        creator: alice,
        to: alice,
        data_uri: "data:," + JSON.generate(collection_data)
      )

      collection_results = import_l1_block([collection_spec], esip_overrides: { esip6_is_enabled: true })
      collection_id = collection_results[:ethscription_ids].first
      expect(collection_id).to be_present
      metadata_before_edit = get_collection_metadata(collection_id)
      expect(metadata_before_edit[:merkleRoot].downcase).to eq(initial_merkle_root.downcase)

      allowlist_attributes = [{"trait_type" => "Tier", "value" => "Founder"}]
      item_template = {
        "p" => "erc-721-ethscriptions-collection",
        "op" => "add_self_to_collection",
        "collection_id" => collection_id,
        "item" => {
          "item_index" => "0",
          "name" => "Allowlisted Item #0",
          "background_color" => "#abcdef",
          "description" => "Non-owner entry gated by the root",
          "attributes" => allowlist_attributes,
          "merkle_proof" => []
        }
      }

      item_json = JSON.generate(item_template)
      content_hash_hex = "0x#{Eth::Util.keccak256(item_json).unpack1('H*')}"
      attribute_pairs = allowlist_attributes.map { |attr| [attr["trait_type"], attr["value"]] }
      computed_root = compute_single_leaf_root(
        content_hash_hex: content_hash_hex,
        item_index: 0,
        name: item_template["item"]["name"],
        background_color: item_template["item"]["background_color"],
        description: item_template["item"]["description"],
        attributes: attribute_pairs
      )

      edit_payload = {
        "p" => "erc-721-ethscriptions-collection",
        "op" => "edit_collection",
        "collection_id" => collection_id,
        "description" => "",
        "logo_image_uri" => "",
        "banner_image_uri" => "",
        "background_color" => "",
        "website_link" => "",
        "twitter_link" => "",
        "discord_link" => "",
        "merkle_root" => computed_root
      }

      edit_spec = create_input(
        creator: alice,
        to: alice,
        data_uri: "data:," + JSON.generate(edit_payload)
      )

      edit_results = import_l1_block([edit_spec], esip_overrides: { esip6_is_enabled: true })
      expect(edit_results[:l2_receipts].first[:status]).to eq('0x1')

      metadata_after_edit = get_collection_metadata(collection_id)
      expect(metadata_after_edit[:merkleRoot].downcase).to eq(computed_root.downcase)

      second_spec = create_input(
        creator: bob,
        to: bob,
        data_uri: "data:," + item_json
      )

      success_results = import_l1_block([second_spec], esip_overrides: { esip6_is_enabled: true })
      success_receipt = success_results[:l2_receipts].first
      success_events = ProtocolEventReader.parse_receipt_events(success_receipt)
      expect(success_events.any? { |e| e[:event] == 'ProtocolHandlerSuccess' }).to eq(true)
      added_event = success_events.find { |e| e[:event] == 'ItemsAdded' }
      expect(added_event).not_to be_nil
      expect(added_event[:count]).to eq(1)

      added_item_id = success_results[:ethscription_ids].first
      stored_item = get_collection_item(collection_id, 0)
      expect(stored_item[:ethscriptionId]).to eq(added_item_id)

      expect(get_collection_metadata(collection_id)[:merkleRoot].downcase).to eq(computed_root.downcase)
    end
  end

  def compute_single_leaf_root(content_hash_hex:, item_index:, name:, background_color:, description:, attributes:)
    content_hash_bytes = [content_hash_hex.delete_prefix('0x')].pack('H*')
    encoded = Eth::Abi.encode(
      ['bytes32', 'uint256', 'string', 'string', 'string', '(string,string)[]'],
      [content_hash_bytes, item_index, name, background_color, description, attributes]
    )
    "0x#{Eth::Util.keccak256(encoded).unpack1('H*')}"
  end
end
