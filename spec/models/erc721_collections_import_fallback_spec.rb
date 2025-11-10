require 'rails_helper'

RSpec.describe Erc721EthscriptionsCollectionParser do
  describe 'ID-aware import fallback and normal add flow' do
    let(:zero_merkle_root) { '0x' + '0' * 64 }
    let(:leader_id) { '0x' + '1' * 64 }
    let(:member_id) { '0x' + '2' * 64 }

    let(:collections_json) do
      {
        'Test Collection' => {
          'name' => 'Test Collection',
          'slug' => 'TEST',
          'description' => 'Imported collection',
          'logo_image_uri' => '',
          'banner_image_uri' => '',
          'website_link' => 'https://example.com',
          'twitter_link' => '',
        'discord_link' => '',
        'background_color' => '#FFFFFF',
        'total_supply' => 2,
        'merkle_root' => zero_merkle_root
        }
      }
    end

    let(:items_json) do
      {
        leader_id => {
          'index' => 0,
          'name' => 'Item Zero',
          'description' => 'First',
          'attributes' => [ { 'trait_type' => 'Type', 'value' => 'Genesis' } ],
          'ethscription_number' => 100,
          'collection_name' => 'Test Collection',
          'collection_slug' => 'TEST'
        },
        member_id => {
          'index' => 1,
          'name' => 'Item One',
          'description' => 'Second',
          'attributes' => [],
          'ethscription_number' => 200,
          'collection_name' => 'Test Collection',
          'collection_slug' => 'TEST'
        }
      }
    end

    let(:items_path) { Rails.root.join('tmp', 'spec_import_items.json').to_s }
    let(:collections_path) { Rails.root.join('tmp', 'spec_import_collections.json').to_s }

    before do
      FileUtils.mkdir_p(File.dirname(items_path))
      File.write(items_path, JSON.pretty_generate(items_json))
      File.write(collections_path, JSON.pretty_generate(collections_json))
      stub_const('Erc721EthscriptionsCollectionParser::DEFAULT_ITEMS_PATH', items_path)
      stub_const('Erc721EthscriptionsCollectionParser::DEFAULT_COLLECTIONS_PATH', collections_path)
    end

    it 'builds create_collection_and_add_self for the leader via import fallback' do
      protocol, operation, encoded = ProtocolParser.for_calldata(
        'data:,{}',
        ethscription_id: ByteString.from_hex(leader_id)
      )
      expect(protocol).to eq('erc-721-ethscriptions-collection'.b)
      expect(operation).to eq('create_collection_and_add_self'.b)

      decoded = Eth::Abi.decode([
        '((string,string,uint256,string,string,string,string,string,string,string,bytes32),(bytes32,uint256,string,string,string,(string,string)[],bytes32[]))'
      ], encoded)[0]

      metadata = decoded[0]
      item = decoded[1]

      expect(metadata[0]).to eq('Test Collection') # name
      expect(metadata[1]).to eq('TEST')            # symbol (from slug)
      expect(metadata[2]).to eq(2)                 # maxSupply from total_supply

      # Item now has contentHash as first field
      expect(item[1]).to eq(0)                     # item index (now at position 1)
      expect(item[2]).to eq('Item Zero')           # name (now at position 2)
      expect(item[3]).to eq('')                    # background_color (now at position 3)
    end

    it 'builds add_self_to_collection for a member via import fallback' do
      protocol, operation, encoded = ProtocolParser.for_calldata(
        'data:,{}',
        ethscription_id: ByteString.from_hex(member_id)
      )

      expect(protocol).to eq('erc-721-ethscriptions-collection'.b)
      expect(operation).to eq('add_self_to_collection'.b)

      decoded = Eth::Abi.decode([
        '(bytes32,(bytes32,uint256,string,string,string,(string,string)[],bytes32[]))'
      ], encoded)[0]

      collection_id = decoded[0]
      item = decoded[1]

      expect(collection_id.unpack1('H*')).to eq(leader_id[2..])
      # Item now has contentHash as first field
      expect(item[1]).to eq(1)                     # item index (now at position 1)
      expect(item[2]).to eq('Item One')            # name (now at position 2)
      expect(item[3]).to eq('')                    # background_color (now at position 3)
    end

    it 'parses normal content for add_self_to_collection (non-import)' do
      content_json = {
        'p' => 'erc-721-ethscriptions-collection',
        'op' => 'add_self_to_collection',
        'collection_id' => leader_id,
        'item' => {
          'item_index' => '5',
          'name' => 'Normal Item',
          'background_color' => '#000000',
          'description' => 'desc',
          'attributes' => [],
          'merkle_proof' => []
        }
      }

      protocol, operation, encoded = ProtocolParser.for_calldata('data:,' + content_json.to_json)

      expect(protocol).to eq('erc-721-ethscriptions-collection'.b)
      expect(operation).to eq('add_self_to_collection'.b)

      decoded = Eth::Abi.decode([
        '(bytes32,(bytes32,uint256,string,string,string,(string,string)[],bytes32[]))'
      ], encoded)[0]

      expect(decoded[0].unpack1('H*')).to eq(leader_id[2..])
      item = decoded[1]
      # Item now has contentHash as first field
      expect(item[1]).to eq(5)                     # item_index (now at position 1)
      expect(item[2]).to eq('Normal Item')         # name (now at position 2)
      expect(item[3]).to eq('#000000')             # background_color (now at position 3)
      expect(item[4]).to eq('desc')                # description (now at position 4)
    end
  end

  describe 'Live JSON files import fallback' do
    it 'builds create_collection_and_add_self for specific ethscription using live JSON files' do
      # This ethscription should be the leader of a collection in the live JSON files
      specific_id = '0x05aac415994e0e01e66c4970133a51a4cdcea1f3a967743b87e6eb08f2f4d9f9'

      protocol, operation, encoded = ProtocolParser.for_calldata(
        'data:,{}',
        ethscription_id: ByteString.from_hex(specific_id)
      )
      expect(protocol).to eq('erc-721-ethscriptions-collection'.b)
      expect(operation).to eq('create_collection_and_add_self'.b)

      # Decode to verify it's properly formed
      decoded = Eth::Abi.decode([
        '((string,string,uint256,string,string,string,string,string,string,string,bytes32),(bytes32,uint256,string,string,string,(string,string)[],bytes32[]))'
      ], encoded)[0]

      metadata = decoded[0]
      item = decoded[1]

      # Should have valid metadata
      expect(metadata[0]).to be_a(String) # name
      expect(metadata[0].length).to be > 0
      expect(metadata[1]).to be_a(String) # symbol
      expect(metadata[2]).to be_a(Integer) # maxSupply

      # Should have valid item data (contentHash is first field now)
      expect(item[0]).to be_a(String)  # content_hash (packed bytes)
      expect(item[1]).to be_a(Integer) # item_index
      expect(item[2]).to be_a(String)  # name
      expect(item[3]).to be_a(String)  # background_color
      expect(item[4]).to be_a(String)  # description
      expect(item[5]).to be_an(Array)  # attributes
      expect(item[6]).to be_an(Array)  # merkle_proof
    end
  end

  describe 'End-to-end collection creation with live JSON', type: :integration do
    include EthscriptionsTestHelper

    let(:creator) { valid_address("creator") }
    let(:specific_id) { '0x05aac415994e0e01e66c4970133a51a4cdcea1f3a967743b87e6eb08f2f4d9f9' }

    it 'creates collection and adds ethscription using import fallback for specific ID' do
      # Create ethscription with PNG content - should use import fallback
      tx_spec = l1_tx(
        creator: creator,
        to: creator,
        input: '0x646174613a696d6167652f706e673b6261736536342c6956424f5277304b47676f414141414e535568455567414141426741414141594341594141414467647a3334414141416d306c4551565234326d4e6747495467507854547876426c65546f30737742734f4b30732b4e38614a6b637a4331414d52374b414b7062387637327841593568467344346c466f434e2b6a35365a556f6c694262536f6b6c47495a6a7778526251416a5431594b37642b38326b4755426575516969354672415959724c38314e774370474651746f4555542f36526f485741796b6e51563053365a49355245364a7438435a494f4f48547547675239467135466b43663139514d33777835725a4b48457473525a517435716b6867554152366347615565684f443441414141415355564f524b35435949493d',
        tx_hash: specific_id,
        expect: :success
      )

      results = import_l1_block([tx_spec], esip_overrides: { esip6_is_enabled: true })

      # Verify ethscription was created
      expect(results[:ethscription_ids]).to include(specific_id)
      expect(results[:l2_receipts].first[:status]).to eq('0x1'), "L2 transaction should succeed"

      # Parse events to verify collection creation and item addition
      require_relative '../../lib/protocol_event_reader'
      events = ProtocolEventReader.parse_receipt_events(results[:l2_receipts].first)

      # Should have CollectionCreated event
      collection_created = events.find { |e| e[:event] == 'CollectionCreated' }
      expect(collection_created).not_to be_nil, "Should emit CollectionCreated event"
      expect(collection_created[:collection_id]).to eq(specific_id)

      # Should have ItemsAdded event
      items_added = events.find { |e| e[:event] == 'ItemsAdded' }
      expect(items_added).not_to be_nil, "Should emit ItemsAdded event"
      expect(items_added[:collection_id]).to eq(specific_id)
      expect(items_added[:count]).to eq(1), "Should add 1 item"

      # Should have protocol success
      protocol_success = events.any? { |e| e[:event] == 'ProtocolHandlerSuccess' }
      expect(protocol_success).to eq(true), "Protocol operation should succeed"

      # Verify collection state via eth_call
      collection_state = get_collection_state(specific_id)
      expect(collection_state[:collectionContract]).not_to eq('0x0000000000000000000000000000000000000000')
      expect(collection_state[:currentSize]).to eq(1), "Collection should have 1 item"
    end
  end
end
