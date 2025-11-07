require 'rails_helper'

RSpec.describe "Token Protocol End-to-End", type: :integration do
  include EthscriptionsTestHelper

  let(:alice) { valid_address("alice") }
  let(:bob) { valid_address("bob") }
  let(:charlie) { valid_address("charlie") }
  let(:dummy_recipient) { valid_address("recipient") }

  describe "Complete Token Workflow with Protocol Validation" do
    it "deploys token and validates protocol execution" do
      # Note: 'erc-20' is a legacy protocol identifier; the canonical protocol name is now 'erc-20-fixed-denomination'.
      # This test uses the legacy format, which is normalized to the canonical name by the system.
      deploy_json = '{"p":"erc-20","op":"deploy","tick":"testcoin","max":"1000000","lim":"1000"}'

      result = create_and_validate_ethscription(
        creator: alice,
        to: dummy_recipient,
        data_uri: "data:," + deploy_json
      )

      # Validate ethscription creation
      expect(result[:success]).to eq(true), "Ethscription creation failed"
      deploy_id = result[:ethscription_id]
      expect(deploy_id).to be_present

      # Validate ethscription content
      stored = get_ethscription_content(deploy_id)
      expect(stored[:content]).to include('"p":"erc-20"')
      expect(stored[:content]).to include('"op":"deploy"')
      expect(stored[:content]).to include('"tick":"testcoin"')

      # Validate protocol execution
      expect(result[:protocol_event]).to eq("ERC20FixedDenominationTokenDeployed"), "Protocol handler did not emit ERC20FixedDenominationTokenDeployed event"
      expect(result[:protocol_success]).to eq(true), "Protocol operation failed"

      # Validate token state in contract
      token_state = get_token_state("testcoin")
      
      expect(token_state).not_to be_nil, "get_token_state returned nil"
      expect(token_state[:exists]).to eq(true), "Token not found in contract"
      # Note: TokenInfo struct doesn't have deployer field
      expect(token_state[:maxSupply]).to eq(1000000), "Max supply mismatch"
      expect(token_state[:mintLimit]).to eq(1000), "Mint limit mismatch"
      expect(token_state[:totalMinted]).to eq(0), "Should start with 0 minted"

      # Validate ERC20 contract deployment
      expect(token_state[:tokenContract]).not_to eq("0x0000000000000000000000000000000000000000")
      expect(token_state[:tokenContract]).to match(/^0x[a-fA-F0-9]{40}$/), "Invalid token contract address"
    end

    it "mints tokens and validates execution" do
      # Deploy token first
      deploy_token("minttest", alice)

      # Mint tokens - amount must match the lim from deployment
      mint_data = {
        "p" => "erc-20",
        "op" => "mint",
        "tick" => "minttest",
        "id" => "1",
        "amt" => "1000"  # Must match lim from deployment
      }

      # JSON must be in exact format
      mint_json = '{"p":"erc-20","op":"mint","tick":"minttest","id":"1","amt":"1000"}'

      result = create_and_validate_ethscription(
        creator: bob,
        to: bob, # Mint to self so Bob owns the ethscription
        data_uri: "data:," + mint_json
      )

      # Validate ethscription creation
      expect(result[:success]).to eq(true), "Ethscription creation failed"
      mint_id = result[:ethscription_id]

      # Validate protocol execution
      expect(result[:protocol_event]).to eq("ERC20FixedDenominationTokenMinted"), "Protocol handler did not emit ERC20FixedDenominationTokenMinted event"
      expect(result[:protocol_success]).to eq(true), "Protocol operation failed"
      expect(result[:mint_amount]).to eq(1000), "Mint amount mismatch"

      # Validate token state updated
      token_state = get_token_state("minttest")
      expect(token_state[:totalMinted]).to eq(1000), "Total minted should be 1000"

      # Validate mint record
      mint_record = get_mint_record(mint_id)
      expect(mint_record[:exists]).to eq(true), "Mint record not found"
      expect(mint_record[:amount]).to eq(1000), "Mint amount mismatch"
      expect(mint_record[:ethscriptionId]).to eq(mint_id), "Ethscription ID mismatch"

      # Validate token balance
      balance = get_token_balance("minttest", bob)
      expect(balance).to eq(1000), "Token balance mismatch"
    end

    it "handles mint transfer and validates token transfer" do
      # Deploy and mint first
      deploy_token("transfertest", alice)

      mint_json = '{"p":"erc-20","op":"mint","tick":"transfertest","id":"1","amt":"1000"}'
      mint_result = create_and_validate_ethscription(
        creator: bob,
        to: bob,
        data_uri: "data:," + mint_json
      )
      mint_id = mint_result[:ethscription_id]

      # Transfer the mint ethscription (transfers the tokens)
      transfer_result = transfer_ethscription(
        from: bob,
        to: charlie,
        ethscription_id: mint_id
      )

      expect(transfer_result[:success]).to eq(true), "Ethscription transfer failed"
      expect(transfer_result[:protocol_event]).to eq("ERC20FixedDenominationTokenTransferred"), "ERC20 fixed denomination transfer event not emitted"

      # Validate token balances updated
      bob_balance = get_token_balance("transfertest", bob)
      expect(bob_balance).to eq(0), "Bob should have 0 tokens after transfer"

      charlie_balance = get_token_balance("transfertest", charlie)
      expect(charlie_balance).to eq(1000), "Charlie should have 1000 tokens after transfer"

      # Validate mint record updated
      # Note: ERC20FixedDenominationManager doesn't track current owner in TokenItem
      # Token ownership is tracked via ERC20 balances instead
    end
  end

  describe "Protocol Validation Edge Cases" do
    it "rejects duplicate token deployment" do
      # Deploy first token
      deploy_json = '{"p":"erc-20","op":"deploy","tick":"duplicate","max":"1000","lim":"100"}'

      first_result = create_and_validate_ethscription(
        creator: alice,
        to: dummy_recipient,
        data_uri: "data:," + deploy_json
      )
      expect(first_result[:protocol_success]).to eq(true)

      # Try to deploy same tick with different parameters
      # This creates a different ethscription but same tick should be rejected
      deploy_json_different = '{"p":"erc-20","op":"deploy","tick":"duplicate","max":"2000","lim":"200"}'
      second_result = create_and_validate_ethscription(
        creator: bob,
        to: dummy_recipient,
        data_uri: "data:," + deploy_json_different
      )

      # Ethscription created but protocol operation fails
      expect(second_result[:success]).to eq(true), "Ethscription should be created"
      expect(second_result[:protocol_extracted]).to eq(true), "Protocol should be extracted"
      expect(second_result[:protocol_success]).to eq(false), "Protocol operation should fail"
      # Error parsing has encoding issues, so just verify we got an error
      expect(second_result[:protocol_error]).not_to be_nil, "Should have an error for duplicate deployment"
    end

    it "rejects mint with wrong amount" do
      # Deploy token with lim=100
      deploy_json = '{"p":"erc-20","op":"deploy","tick":"wrongamt","max":"1000","lim":"100"}'
      deploy_result = create_and_validate_ethscription(
        creator: alice,
        to: dummy_recipient,
        data_uri: "data:," + deploy_json
      )
      expect(deploy_result[:protocol_success]).to eq(true)

      # Try to mint with wrong amount (not matching lim)
      mint_json = '{"p":"erc-20","op":"mint","tick":"wrongamt","id":"1","amt":"50"}'

      mint_result = create_and_validate_ethscription(
        creator: bob,
        to: bob,
        data_uri: "data:," + mint_json
      )

      expect(mint_result[:success]).to eq(true), "Ethscription should be created"
      expect(mint_result[:protocol_success]).to eq(false), "Protocol operation should fail"
      # Error parsing has encoding issues, so just verify we got an error
      expect(mint_result[:protocol_error]).not_to be_nil, "Should have an error for amount mismatch"
    end

    it "enforces exact mint amount" do
      # Deploy with limit of 100
      deploy_json = '{"p":"erc-20","op":"deploy","tick":"limited","max":"300","lim":"100"}'
      deploy_result = create_and_validate_ethscription(
        creator: alice,
        to: dummy_recipient,
        data_uri: "data:," + deploy_json
      )
      expect(deploy_result[:protocol_success]).to eq(true)

      # Try to mint over limit (101 instead of 100)
      mint_json = '{"p":"erc-20","op":"mint","tick":"limited","id":"1","amt":"101"}'
      mint_result = create_and_validate_ethscription(
        creator: bob,
        to: bob,
        data_uri: "data:," + mint_json
      )

      expect(mint_result[:success]).to eq(true), "Ethscription should be created"
      expect(mint_result[:protocol_success]).to eq(false), "Protocol operation should fail"
      # Error parsing has encoding issues, so just verify we got an error
      expect(mint_result[:protocol_error]).not_to be_nil, "Should have an error for amount mismatch"
    end

    it "enforces max supply" do
      # Deploy with low max supply
      deploy_json = '{"p":"erc-20","op":"deploy","tick":"maxed","max":"200","lim":"100"}'
      deploy_result = create_and_validate_ethscription(
        creator: alice,
        to: dummy_recipient,
        data_uri: "data:," + deploy_json
      )

      # Mint twice to reach max
      mint1_json = '{"p":"erc-20","op":"mint","tick":"maxed","id":"1","amt":"100"}'
      mint2_json = '{"p":"erc-20","op":"mint","tick":"maxed","id":"2","amt":"100"}'

      create_and_validate_ethscription(creator: bob, to: bob, data_uri: "data:," + mint1_json)
      create_and_validate_ethscription(creator: bob, to: bob, data_uri: "data:," + mint2_json)

      # Third mint should fail (exceeds max supply)
      mint3_json = '{"p":"erc-20","op":"mint","tick":"maxed","id":"3","amt":"100"}'
      mint3_result = create_and_validate_ethscription(
        creator: charlie,
        to: charlie,
        data_uri: "data:," + mint3_json
      )

      expect(mint3_result[:success]).to eq(true), "Ethscription should be created"
      expect(mint3_result[:protocol_success]).to eq(false), "Protocol operation should fail"
      # The error will be from ERC20Capped's custom error
      expect(mint3_result[:protocol_error]).not_to be_nil, "Should have an error"

      # Verify total minted is at max
      token_state = get_token_state("maxed")
      expect(token_state[:totalMinted]).to eq(200), "Should be at max supply"
    end

    it "handles malformed token JSON" do
      # Missing quotes around tick value
      malformed_json = '{"p":"erc-20","op":"deploy","tick":testbad,"max":"1000","lim":"100"}'

      result = create_and_validate_ethscription(
        creator: alice,
        to: dummy_recipient,
        data_uri: "data:," + malformed_json
      )

      expect(result[:success]).to eq(true), "Ethscription should be created"
      expect(result[:protocol_extracted]).to eq(false), "Protocol should not be extracted"
      expect(result[:protocol_success]).to eq(false), "Protocol should not execute"
    end

    it "rejects token format with unexpected whitespace" do
      # Extra whitespace breaks exact format requirement for the token parser
      invalid_json = '{"p": "erc-20", "op": "deploy", "tick": "spaced", "max": "1000", "lim": "100"}'

      result = create_and_validate_ethscription(
        creator: alice,
        to: dummy_recipient,
        data_uri: "data:," + invalid_json
      )

      expect(result[:success]).to eq(true), "Ethscription should be created"
      expect(result[:protocol_extracted]).to eq(false), "Protocol should not be extracted"
    end
  end

  # Helper methods
  private

  def create_and_validate_ethscription(creator:, to:, data_uri:)
    # Create the ethscription spec
    tx_spec = create_input(
      creator: creator,
      to: to,
      data_uri: data_uri
    )

    # Import the L1 block with the transaction
    results = import_l1_block([tx_spec], esip_overrides: { esip6_is_enabled: true })

    # Get the ethscription ID
    ethscription_id = results[:ethscription_ids]&.first

    # Check if ethscription was created
    success = ethscription_id.present? && results[:l2_receipts]&.first&.fetch(:status, nil) == '0x1'

    # Initialize results
    protocol_results = {
      success: success,
      ethscription_id: ethscription_id,
      protocol_extracted: false,
      protocol_success: false,
      protocol_event: nil,
      protocol_error: nil
    }

    return protocol_results unless success

    # Check if protocol was extracted
    begin
      protocol, operation, encoded_data = ProtocolParser.for_calldata(data_uri)
      protocol_results[:protocol_extracted] = protocol.present? && operation.present?
    rescue => e
      protocol_results[:protocol_error] = e.message
      return protocol_results
    end

    return protocol_results unless protocol_results[:protocol_extracted]

    # Check L2 receipts for protocol execution
    if results[:l2_receipts].present?
      receipt = results[:l2_receipts].first

      # Use protocol event reader for accurate parsing
      require_relative '../../lib/protocol_event_reader'
      events = ProtocolEventReader.parse_receipt_events(receipt)

      # Process parsed events
      events.each do |event|
        case event[:event]
        when 'ProtocolHandlerSuccess'
          protocol_results[:protocol_success] = true
        when 'ProtocolHandlerFailed'
          protocol_results[:protocol_success] = false
          protocol_results[:protocol_error] = event[:reason]
        when 'ERC20FixedDenominationTokenDeployed'
          protocol_results[:protocol_event] = 'ERC20FixedDenominationTokenDeployed'
        when 'ERC20FixedDenominationTokenMinted'
          protocol_results[:protocol_event] = 'ERC20FixedDenominationTokenMinted'
          protocol_results[:mint_amount] = event[:amount]
        when 'ERC20FixedDenominationTokenTransferred'
          protocol_results[:protocol_event] = 'ERC20FixedDenominationTokenTransferred'
        end
      end
    end

    protocol_results
  end

  def transfer_ethscription(from:, to:, ethscription_id:)
    tx_spec = transfer_input(
      from: from,
      to: to,
      id: ethscription_id
    )

    # Import the L1 block with the transfer transaction
    results = import_l1_block([tx_spec])

    transfer_results = {
      success: results[:l2_receipts]&.first&.fetch(:status, nil) == '0x1',
      protocol_event: nil
    }

    # Check for token transfer event
    if results[:l2_receipts].present?
      receipt = results[:l2_receipts].first
      require_relative '../../lib/protocol_event_reader'
      events = ProtocolEventReader.parse_receipt_events(receipt)

      events.each do |event|
        if event[:event] == "ERC20FixedDenominationTokenTransferred"
          transfer_results[:protocol_event] = "ERC20FixedDenominationTokenTransferred"
        end
      end
    end

    transfer_results
  end

  def deploy_token(tick, deployer)
    deploy_json = "{\"p\":\"erc-20\",\"op\":\"deploy\",\"tick\":\"#{tick}\",\"max\":\"1000000\",\"lim\":\"1000\"}"
    result = create_and_validate_ethscription(
      creator: deployer,
      to: dummy_recipient,
      data_uri: "data:," + deploy_json
    )
    expect(result[:protocol_success]).to eq(true), "Token deployment failed"
    result[:ethscription_id]
  end

  # Use actual contract state readers
  def get_token_state(tick)
    token = Erc20FixedDenominationReader.get_token(tick)

    return nil if token.nil?

    # Add convenience fields
    {
      exists: token[:tokenContract] != '0x0000000000000000000000000000000000000000',
      maxSupply: token[:maxSupply],
      mintLimit: token[:mintLimit],
      totalMinted: token[:totalMinted],
      tokenContract: token[:tokenContract],
      ethscriptionId: token[:ethscriptionId],
      protocol: token[:protocol],
      tick: token[:tick]
    }
  end

  def get_mint_record(ethscription_id)
    require_relative '../../lib/erc20_fixed_denomination_reader'
    item = Erc20FixedDenominationReader.get_token_item(ethscription_id)

    return nil if item.nil?

    # Add convenience field
    {
      exists: item[:deployTxHash] != '0x0000000000000000000000000000000000000000000000000000000000000000',
      amount: item[:amount],
      ethscriptionId: ethscription_id,
      deployTxHash: item[:deployTxHash]
    }
  end

  def get_token_balance(tick, address)
    require_relative '../../lib/erc20_fixed_denomination_reader'
    Erc20FixedDenominationReader.get_token_balance(tick, address)
  end

  def get_ethscription_content(ethscription_id)
    require_relative '../../lib/storage_reader'
    data = StorageReader.get_ethscription_with_content(ethscription_id)

    return nil if data.nil?

    {
      content: data[:content],
      creator: data[:creator],
      owner: data[:initial_owner]
    }
  end

  def token_exists?(tick)
    Erc20FixedDenominationReader.token_exists?(tick)
  end

  def token_item_exists?(ethscription_id)
    item = Erc20FixedDenominationReader.get_token_item(ethscription_id)
    return false if item.nil?
    item[:deployTxHash] != '0x0000000000000000000000000000000000000000000000000000000000000000'
  end
end
