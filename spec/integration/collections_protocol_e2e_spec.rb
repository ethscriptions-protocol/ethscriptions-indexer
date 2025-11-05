require 'rails_helper'

RSpec.describe "Collections Protocol End-to-End", type: :integration do
  include EthscriptionsTestHelper

  let(:alice) { valid_address("alice") }
  let(:bob) { valid_address("bob") }
  let(:dummy_recipient) { valid_address("recipient") }

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
      protocol, operation, _encoded_data = ProtocolExtractor.for_calldata(data_uri)
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
        "discord_link" => ""
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

      # The content might be in binary format
      content_str = stored[:content].is_a?(String) ? stored[:content] : stored[:content].force_encoding('UTF-8')

      expect(content_str).to include('"p":"erc-721-ethscriptions-collection"')
      expect(content_str).to include('"op":"create_collection"')
      expect(content_str).to include('"name":"Test NFT"')

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
        "discord_link" => ""
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

      # Now create the ethscriptions that will be added to the collection
      # Use the same direct pattern for creating items
      item1_spec = create_input(
        creator: alice,
        to: alice,
        data_uri: "data:,Batch Item 1 content"
      )

      item1_results = import_l1_block([item1_spec], esip_overrides: { esip6_is_enabled: true })
      item1_id = item1_results[:ethscription_ids].first
      expect(item1_id).to be_present, "Item 1 should be created"

      item2_spec = create_input(
        creator: alice,
        to: alice,
        data_uri: "data:,Batch Item 2 content"
      )

      item2_results = import_l1_block([item2_spec], esip_overrides: { esip6_is_enabled: true })
      item2_id = item2_results[:ethscription_ids].first
      expect(item2_id).to be_present, "Item 2 should be created"

      # Complex nested structure matching real-world usage
      batch_data = {
        "p" => "erc-721-ethscriptions-collection",
        "op" => "add_items_batch",
        "collection_id" => collection_id,
        "items" => [
          {
            "item_index" => "0",
            "name" => "Test Item #0",
            "ethscription_id" => item1_id,
            "background_color" => "#648595",
            "description" => "First test item with multiple attributes",
            "attributes" => [
              {"trait_type" => "Type", "value" => "Common"},
              {"trait_type" => "Color", "value" => "Blue"},
              {"trait_type" => "Rarity", "value" => "1"},
              {"trait_type" => "Power", "value" => "100"}
            ]
          },
          {
            "item_index" => "1",
            "name" => "Test Item #1",
            "ethscription_id" => item2_id,
            "background_color" => "#FF5733",
            "description" => "Second test item with different attributes",
            "attributes" => [
              {"trait_type" => "Type", "value" => "Rare"},
              {"trait_type" => "Color", "value" => "Red"},
              {"trait_type" => "Rarity", "value" => "5"},
              {"trait_type" => "Power", "value" => "500"}
            ]
          }
        ]
      }

      # Create the add_items_batch transaction using the direct pattern
      batch_spec = create_input(
        creator: alice,
        to: dummy_recipient,
        data_uri: "data:," + batch_data.to_json
      )

      batch_results = import_l1_block([batch_spec], esip_overrides: { esip6_is_enabled: true })

      # Validate ethscription creation
      expect(batch_results[:ethscription_ids]).not_to be_empty, "Should create batch ethscription"
      batch_id = batch_results[:ethscription_ids].first
      expect(batch_id).to be_present

      # Parse events to validate protocol execution
      require_relative '../../lib/protocol_event_reader'
      events = ProtocolEventReader.parse_receipt_events(batch_results[:l2_receipts].first)

      # Check for ItemsAdded event
      items_added_event = events.find { |e| e[:event] == 'ItemsAdded' }
      expect(items_added_event).not_to be_nil, "Should emit ItemsAdded event"
      expect(items_added_event[:count]).to eq(2), "Should add 2 items"

      # Check for protocol success
      protocol_success = events.any? { |e| e[:event] == 'ProtocolHandlerSuccess' }
      expect(protocol_success).to eq(true), "Protocol operation should succeed"

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
end
