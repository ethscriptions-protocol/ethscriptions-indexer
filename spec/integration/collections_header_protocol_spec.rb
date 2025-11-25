require 'rails_helper'
require 'base64'
require_relative '../../lib/protocol_event_reader'

RSpec.describe "Header-Based Collections Protocol", type: :integration do
  include EthscriptionsTestHelper

  let(:alice) { valid_address("alice") }
  let(:bob) { valid_address("bob") }
  let(:carol) { valid_address("carol") }
  let(:media_type) { 'image/png' }
  let(:force_merkle_sender) { "0x0000000000000000000000000000000000000042" }
  let(:zero_merkle_root) { '0x' + '0' * 64 }

  # Small "image" payloads live in the data URI body; protocol data lives in headers
  let(:items_manifest) do
    [
      {
        item_index: 0,
        name: "Header Genesis",
        background_color: "#111111",
        description: "Leader image stored with header metadata",
        attributes: [
          {"trait_type" => "Tier", "value" => "Genesis"},
          {"trait_type" => "Artist", "value" => "Alice"}
        ],
        base64_content: Base64.strict_encode64("header-genesis-image")
      },
      {
        item_index: 1,
        name: "Header Entry #1",
        background_color: "#222222",
        description: "Bob adds via header path",
        attributes: [
          {"trait_type" => "Tier", "value" => "Member"},
          {"trait_type" => "Artist", "value" => "Bob"}
        ],
        base64_content: Base64.strict_encode64("header-bob-image")
      },
      {
        item_index: 2,
        name: "Header Entry #2",
        background_color: "#333333",
        description: "Carol adds via header path",
        attributes: [
          {"trait_type" => "Tier", "value" => "Member"},
          {"trait_type" => "Artist", "value" => "Carol"}
        ],
        base64_content: Base64.strict_encode64("header-carol-image")
      }
    ]
  end

  let(:merkle_plan) { build_merkle_plan(items_manifest) }
  let(:merkle_root) { merkle_plan[:root] }
  let(:proofs) { merkle_plan[:proofs] }

  it "mints collection/items from headers and enforces merkle proofs" do
    collection_uri = header_data_uri(
      op: 'create_collection_and_add_self',
      payload: {
        "metadata" => metadata_payload(merkle_root: merkle_root, initial_owner: alice),
        "item" => item_payload(items_manifest[0], proofs[0])
      },
      content_base64: items_manifest[0][:base64_content]
    )

    creation_results = import_l1_block(
      [create_input(creator: alice, to: alice, data_uri: collection_uri)],
      esip_overrides: { esip6_is_enabled: true }
    )
    creation_receipt = creation_results[:l2_receipts].first
    expect(creation_receipt[:status]).to eq('0x1')

    collection_id = creation_results[:ethscription_ids].first
    expect(collection_id).to be_present
    metadata = get_collection_metadata(collection_id)
    expect(metadata[:merkleRoot].downcase).to eq(merkle_root.downcase)

    leader_item = get_collection_item(collection_id, 0)
    expect(leader_item[:ethscriptionId]).to eq(collection_id)
    expect(leader_item[:name]).to eq(items_manifest[0][:name])

    bob_uri = header_data_uri(
      op: 'add_self_to_collection',
      payload: add_item_payload(collection_id, items_manifest[1], proofs[1]),
      content_base64: items_manifest[1][:base64_content]
    )
    bob_results = import_l1_block(
      [create_input(creator: bob, to: bob, data_uri: bob_uri)],
      esip_overrides: { esip6_is_enabled: true }
    )
    bob_receipt = bob_results[:l2_receipts].first
    expect(bob_receipt[:status]).to eq('0x1')
    bob_events = ProtocolEventReader.parse_receipt_events(bob_receipt)
    expect(bob_events.any? { |e| e[:event] == 'ItemsAdded' }).to eq(true)
    expect(bob_events.any? { |e| e[:event] == 'ProtocolHandlerSuccess' }).to eq(true)
    item1_id = bob_results[:ethscription_ids].first
    expect(get_collection_item(collection_id, 1)[:ethscriptionId]).to eq(item1_id)

    carol_uri = header_data_uri(
      op: 'add_self_to_collection',
      payload: add_item_payload(collection_id, items_manifest[2], proofs[2]),
      content_base64: items_manifest[2][:base64_content]
    )
    carol_results = import_l1_block(
      [create_input(creator: carol, to: carol, data_uri: carol_uri)],
      esip_overrides: { esip6_is_enabled: true }
    )
    carol_receipt = carol_results[:l2_receipts].first
    expect(carol_receipt[:status]).to eq('0x1')
    carol_events = ProtocolEventReader.parse_receipt_events(carol_receipt)
    expect(carol_events.any? { |e| e[:event] == 'ItemsAdded' }).to eq(true)
    expect(carol_events.any? { |e| e[:event] == 'ProtocolHandlerSuccess' }).to eq(true)
    item2_id = carol_results[:ethscription_ids].first
    expect(get_collection_item(collection_id, 2)[:ethscriptionId]).to eq(item2_id)

    expect(get_collection_state(collection_id)[:currentSize]).to eq(3)

    forged_item = {
      item_index: 3,
      name: "Forged Entry",
      background_color: "#444444",
      description: "Should fail merkle proof",
      attributes: [
        {"trait_type" => "Tier", "value" => "Spoof"},
        {"trait_type" => "Artist", "value" => "Mallory"}
      ],
      base64_content: Base64.strict_encode64("forged-header-image")
    }

    forged_uri = header_data_uri(
      op: 'add_self_to_collection',
      payload: add_item_payload(collection_id, forged_item, proofs[0]), # wrong proof on purpose
      content_base64: forged_item[:base64_content]
    )
    # Use the hard-coded force-merkle sender so enforcement applies even in import mode
    forged_results = import_l1_block(
      [create_input(creator: force_merkle_sender, to: force_merkle_sender, data_uri: forged_uri)],
      esip_overrides: { esip6_is_enabled: true }
    )
    forged_receipt = forged_results[:l2_receipts].first
    forged_events = ProtocolEventReader.parse_receipt_events(forged_receipt)

    failure = forged_events.find { |e| e[:event] == 'ProtocolHandlerFailed' }
    expect(failure).not_to be_nil
    expect(failure[:reason].to_s).to match(/Invalid Merkle proof/i)
    expect(get_collection_state(collection_id)[:currentSize]).to eq(3)
  end

  context 'unhappy paths' do
    describe 'content hash mismatch' do
      it 'rejects when actual image differs from merkle leaf content' do
        collection_id = create_header_collection(owner: alice, merkle_root: merkle_root)

        # Use correct proof and metadata for items_manifest[1], but WRONG image content
        tampered_content = Base64.strict_encode64("tampered-image-not-header-bob-image")

        uri = header_data_uri(
          op: 'add_self_to_collection',
          payload: add_item_payload(collection_id, items_manifest[1], proofs[1]),
          content_base64: tampered_content
        )

        results = import_l1_block(
          [create_input(creator: force_merkle_sender, to: force_merkle_sender, data_uri: uri)],
          esip_overrides: { esip6_is_enabled: true }
        )

        expect_protocol_failure(results[:l2_receipts].first, /Invalid Merkle proof/i)
      end
    end

    describe 'collection validation' do
      it 'rejects add to non-existent collection' do
        fake_collection_id = '0x' + 'dead' * 16

        uri = header_data_uri(
          op: 'add_self_to_collection',
          payload: add_item_payload(fake_collection_id, items_manifest[1], proofs[1]),
          content_base64: items_manifest[1][:base64_content]
        )

        results = import_l1_block(
          [create_input(creator: force_merkle_sender, to: force_merkle_sender, data_uri: uri)],
          esip_overrides: { esip6_is_enabled: true }
        )

        expect_protocol_failure(results[:l2_receipts].first, /Collection does not exist/i)
      end

      it 'rejects add to locked collection' do
        collection_id = create_header_collection(owner: alice, merkle_root: merkle_root)

        # Lock the collection
        lock_uri = json_data_uri({
          "p" => "erc-721-ethscriptions-collection",
          "op" => "lock_collection",
          "collection_id" => collection_id
        })
        import_l1_block(
          [create_input(creator: alice, to: alice, data_uri: lock_uri)],
          esip_overrides: { esip6_is_enabled: true }
        )

        # Verify collection is locked
        expect(get_collection_state(collection_id)[:locked]).to eq(true)

        # Try to add item - should fail
        uri = header_data_uri(
          op: 'add_self_to_collection',
          payload: add_item_payload(collection_id, items_manifest[1], proofs[1]),
          content_base64: items_manifest[1][:base64_content]
        )

        results = import_l1_block(
          [create_input(creator: force_merkle_sender, to: force_merkle_sender, data_uri: uri)],
          esip_overrides: { esip6_is_enabled: true }
        )

        expect_protocol_failure(results[:l2_receipts].first, /Collection is locked/i)
      end
    end

    describe 'supply limits' do
      it 'rejects when exceeding max_supply' do
        # Create collection with max_supply of 1 (item 0 already added via create_collection_and_add_self)
        collection_id = create_header_collection(owner: alice, merkle_root: merkle_root, max_supply: "1")

        # Collection already has 1 item (item 0), try to add item 1 - should fail
        uri = header_data_uri(
          op: 'add_self_to_collection',
          payload: add_item_payload(collection_id, items_manifest[1], proofs[1]),
          content_base64: items_manifest[1][:base64_content]
        )

        results = import_l1_block(
          [create_input(creator: force_merkle_sender, to: force_merkle_sender, data_uri: uri)],
          esip_overrides: { esip6_is_enabled: true }
        )

        expect_protocol_failure(results[:l2_receipts].first, /Exceeds max supply/i)
      end
    end

    describe 'item slot conflicts' do
      it 'rejects duplicate item_index' do
        collection_id = create_header_collection(owner: alice, merkle_root: merkle_root)

        # Item 0 is already added via create_header_collection
        # Try to add another item at index 0 (different content)
        different_item_at_index_0 = {
          item_index: 0,
          name: "Different Item",
          background_color: "#999999",
          description: "Trying to overwrite slot 0",
          attributes: [{"trait_type" => "Test", "value" => "Duplicate"}],
          base64_content: Base64.strict_encode64("different-content-for-slot-0")
        }

        # Build a single-item merkle tree for this new item (so proof is valid)
        single_plan = build_merkle_plan([different_item_at_index_0])

        # First, we need to update collection's merkle root to accept this item
        # Actually, let's just use the owner to bypass merkle - simpler test
        uri = header_data_uri(
          op: 'add_self_to_collection',
          payload: add_item_payload(collection_id, different_item_at_index_0, []),
          content_base64: different_item_at_index_0[:base64_content]
        )

        # Owner can bypass merkle, but slot is still taken
        results = import_l1_block(
          [create_input(creator: alice, to: alice, data_uri: uri)],
          esip_overrides: { esip6_is_enabled: true }
        )

        expect_protocol_failure(results[:l2_receipts].first, /Item slot taken/i)
      end
    end

    describe 'merkle proof failures' do
      it 'rejects with empty proof when merkle_root is set' do
        collection_id = create_header_collection(owner: alice, merkle_root: merkle_root)

        # Try to add with empty proof
        uri = header_data_uri(
          op: 'add_self_to_collection',
          payload: add_item_payload(collection_id, items_manifest[1], []),  # Empty proof!
          content_base64: items_manifest[1][:base64_content]
        )

        results = import_l1_block(
          [create_input(creator: force_merkle_sender, to: force_merkle_sender, data_uri: uri)],
          esip_overrides: { esip6_is_enabled: true }
        )

        expect_protocol_failure(results[:l2_receipts].first, /Invalid Merkle proof/i)
      end

      it 'rejects with proof for different item_index' do
        collection_id = create_header_collection(owner: alice, merkle_root: merkle_root)

        # Use item 1's content but item 2's proof
        uri = header_data_uri(
          op: 'add_self_to_collection',
          payload: add_item_payload(collection_id, items_manifest[1], proofs[2]),  # Wrong proof!
          content_base64: items_manifest[1][:base64_content]
        )

        results = import_l1_block(
          [create_input(creator: force_merkle_sender, to: force_merkle_sender, data_uri: uri)],
          esip_overrides: { esip6_is_enabled: true }
        )

        expect_protocol_failure(results[:l2_receipts].first, /Invalid Merkle proof/i)
      end

      it 'rejects when merkle_root is zero and non-owner tries with enforcement' do
        # Create collection with zero merkle root
        collection_id = create_header_collection(owner: alice, merkle_root: zero_merkle_root)

        uri = header_data_uri(
          op: 'add_self_to_collection',
          payload: add_item_payload(collection_id, items_manifest[1], []),
          content_base64: items_manifest[1][:base64_content]
        )

        # force_merkle_sender triggers enforcement, but merkle_root is 0 → "Merkle proof required"
        results = import_l1_block(
          [create_input(creator: force_merkle_sender, to: force_merkle_sender, data_uri: uri)],
          esip_overrides: { esip6_is_enabled: true }
        )

        expect_protocol_failure(results[:l2_receipts].first, /Merkle proof required/i)
      end
    end
  end

  context 'owner privileges' do
    it 'allows owner to add without proof even when merkle_root is set' do
      collection_id = create_header_collection(owner: alice, merkle_root: merkle_root)

      # Owner adds item 1 without a valid proof (empty proof)
      uri = header_data_uri(
        op: 'add_self_to_collection',
        payload: add_item_payload(collection_id, items_manifest[1], []),  # No proof needed for owner
        content_base64: items_manifest[1][:base64_content]
      )

      results = import_l1_block(
        [create_input(creator: alice, to: alice, data_uri: uri)],
        esip_overrides: { esip6_is_enabled: true }
      )

      receipt = results[:l2_receipts].first
      events = ProtocolEventReader.parse_receipt_events(receipt)
      expect(events.any? { |e| e[:event] == 'ProtocolHandlerSuccess' }).to eq(true)
      expect(events.any? { |e| e[:event] == 'ItemsAdded' }).to eq(true)
      expect(get_collection_state(collection_id)[:currentSize]).to eq(2)
    end
  end

  # Helper methods for tests
  def expect_protocol_failure(receipt, error_pattern)
    events = ProtocolEventReader.parse_receipt_events(receipt)
    failure = events.find { |e| e[:event] == 'ProtocolHandlerFailed' }
    expect(failure).not_to be_nil, "Expected ProtocolHandlerFailed event but got: #{events.map { |e| e[:event] }}"
    expect(failure[:reason].to_s).to match(error_pattern),
      "Expected error matching #{error_pattern.inspect}, got: #{failure[:reason]}"
  end

  def create_header_collection(owner:, merkle_root:, max_supply: "4")
    uri = header_data_uri(
      op: 'create_collection_and_add_self',
      payload: {
        "metadata" => metadata_payload(merkle_root: merkle_root, initial_owner: owner).merge("max_supply" => max_supply),
        "item" => item_payload(items_manifest[0], proofs[0])
      },
      content_base64: items_manifest[0][:base64_content]
    )

    results = import_l1_block(
      [create_input(creator: owner, to: owner, data_uri: uri)],
      esip_overrides: { esip6_is_enabled: true }
    )
# binding.irb
    expect(results[:l2_receipts].first[:status]).to eq('0x1'), "Collection creation failed"
    results[:ethscription_ids].first
  end

  def json_data_uri(hash)
    "data:," + JSON.generate(hash)
  end

  def metadata_payload(merkle_root:, initial_owner:, name: nil)
    {
      "name" => name || "Header Merkle Collection #{SecureRandom.hex(4)}",
      "symbol" => "HDR",
      "max_supply" => "4",
      "description" => "Header-based minting flow",
      "logo_image_uri" => "esc://logo/header",
      "banner_image_uri" => "",
      "background_color" => "#000000",
      "website_link" => "https://example.com",
      "twitter_link" => "https://twitter.com/example",
      "discord_link" => "",
      "merkle_root" => merkle_root,
      "initial_owner" => initial_owner
    }
  end

  def item_payload(item, proof)
    {
      "item_index" => item[:item_index].to_s,
      "name" => item[:name],
      "background_color" => item[:background_color],
      "description" => item[:description],
      "attributes" => item[:attributes],
      "merkle_proof" => proof
    }
  end

  def add_item_payload(collection_id, item, proof)
    {
      "collection_id" => collection_id,
      "item" => item_payload(item, proof)
    }
  end

  def header_data_uri(op:, payload:, content_base64:)
    encoded_payload = Base64.strict_encode64(JSON.generate(payload))
    "data:#{media_type};p=erc-721-ethscriptions-collection;op=#{op};d=#{encoded_payload};base64,#{content_base64}"
  end

  def build_merkle_plan(manifest)
    leaves_bin = []
    proofs = {}

    manifest.each do |item|
      content_bytes = Base64.strict_decode64(item[:base64_content])
      content_hash_hex = '0x' + Eth::Util.keccak256(content_bytes).unpack1('H*')
      leaf_hex = compute_leaf_hash(content_hash_hex: content_hash_hex, item: item)
      leaves_bin << [leaf_hex.delete_prefix('0x')].pack('H*')
    end

    levels = build_merkle_tree_levels(leaves_bin)
    root_hex = '0x' + levels.last.first.unpack1('H*')

    leaves_bin.each_with_index do |leaf, idx|
      proofs[idx] = build_proof_for_index(levels, idx)
      raise "invalid merkle proof for leaf #{idx}" unless verify_proof(leaf, proofs[idx], root_hex)
    end

    { root: root_hex, proofs: proofs }
  end

  def build_merkle_tree_levels(leaves)
    return [[''.b]] if leaves.empty?

    levels = [leaves]
    while levels.last.length > 1
      current = levels.last
      next_level = []

      current.each_slice(2) do |left, right|
        right ||= left
        a, b = [left, right].sort
        next_level << Eth::Util.keccak256(a + b)
      end

      levels << next_level
    end

    levels
  end

  def build_proof_for_index(levels, index)
    proof = []
    level_index = index

    levels[0...-1].each do |level|
      sibling_index = level_index ^ 1
      sibling = level[sibling_index] || level[level_index]
      proof << '0x' + sibling.unpack1('H*')
      level_index /= 2
    end

    proof
  end

  def verify_proof(leaf, proof_hex, expected_root_hex)
    computed = leaf

    proof_hex.each do |hex|
      sibling = [hex.delete_prefix('0x')].pack('H*')
      a, b = [computed, sibling].sort
      computed = Eth::Util.keccak256(a + b)
    end

    ('0x' + computed.unpack1('H*')).casecmp(expected_root_hex).zero?
  end

  def compute_leaf_hash(content_hash_hex:, item:)
    content_hash_bytes = [content_hash_hex.delete_prefix('0x')].pack('H*')
    attrs = item[:attributes].map { |attr| [attr["trait_type"], attr["value"]] }

    encoded = Eth::Abi.encode(
      ['bytes32', 'uint256', 'string', 'string', 'string', '(string,string)[]'],
      [content_hash_bytes, item[:item_index], item[:name], item[:background_color], item[:description], attrs]
    )

    '0x' + Eth::Util.keccak256(encoded).unpack1('H*')
  end
end
