require 'rails_helper'

RSpec.describe "Tokens Protocol", type: :integration do
  include EthscriptionsTestHelper

  let(:alice) { valid_address("alice") }
  let(:bob) { valid_address("bob") }
  let(:charlie) { valid_address("charlie") }
  # Ethscriptions are created by sending to any address with data in the input
  # The protocol handler is called automatically by the Ethscriptions contract
  let(:dummy_recipient) { valid_address("recipient") }

  describe "Token Deployment" do
    it "deploys a new token with all parameters" do
      tick = unique_tick('punk')

      token_data = {
        "p" => "erc-20",
        "op" => "deploy",
        "tick" => tick,
        "max" => "21000000",
        "lim" => "1000"
      }

      expect_ethscription_success(
        create_input(
          creator: alice,
          to: dummy_recipient,
          data_uri: "data:," + token_data.to_json
        )
      ) do |results|
        # Verify the ethscription was created
        ethscription_id = results[:ethscription_ids].first
        stored = get_ethscription_content(ethscription_id)

        # Verify the content includes our data
        expect(stored[:content]).to include('"p":"erc-20"')
        expect(stored[:content]).to include('"op":"deploy"')
        expect(stored[:content]).to include("\"tick\":\"#{tick}\"")

        token_state = get_token_state(tick)
        expect(token_state).not_to be_nil
        expect(token_state[:exists]).to eq(true)
        expect(token_state[:maxSupply]).to eq(21_000_000)
        expect(token_state[:mintLimit]).to eq(1000)
        expect(token_state[:totalMinted]).to eq(0)
        expect(token_state[:tokenContract]).to match(/^0x[0-9a-fA-F]{40}$/)
        expect(token_state[:ethscriptionId].downcase).to eq(ethscription_id.downcase)
      end
    end

    it "handles large numbers as strings for JavaScript compatibility" do
      tick = unique_tick('bignum')

      token_data = {
        "p" => "erc-20",
        "op" => "deploy",
        "tick" => tick,
        "max" => "1000000000000000000", # 1e18
        "lim" => "100000000000000000"   # 1e17
      }

      expect_ethscription_success(
        create_input(
          creator: alice,
          to: dummy_recipient,
          data_uri: "data:," + token_data.to_json
        )
      ) do |results|
        # Verify the ethscription was created with large numbers
        ethscription_id = results[:ethscription_ids].first
        stored = get_ethscription_content(ethscription_id)

        expect(stored[:content]).to include('"max":"1000000000000000000"')
        expect(stored[:content]).to include('"lim":"100000000000000000"')
      end
    end

    it "rejects malformed deploy data" do
      # Missing required field
      tick = unique_tick('badtoken')

      malformed_data = {
        "p" => "erc-20",
        "op" => "deploy",
        "tick" => tick
        # Missing max and lim
      }

      expect_protocol_extraction_failure(
        create_input(
          creator: alice,
          to: dummy_recipient,
          data_uri: "data:," + malformed_data.to_json
        )
      ) do |results, stored|
        # Ethscription created but protocol extraction failed
        expect(stored[:content]).to include('"p":"erc-20"')

        expect(token_exists?(tick)).to eq(false)
      end
    end
  end

  describe "Token Minting" do
    context "with shared token deployment" do
      let(:mint_tick) { unique_tick('minttest') }

      before do
        # Deploy a token first
        deploy_data = {
          "p" => "erc-20",
          "op" => "deploy",
          "tick" => mint_tick,
          "max" => "1000000",
          "lim" => "100"
        }

        expect_ethscription_success(
          create_input(
            creator: alice,
            to: dummy_recipient,
            data_uri: "data:," + deploy_data.to_json
          )
        )
      end

      it "mints tokens successfully" do
        mint_data = {
          "p" => "erc-20",
          "op" => "mint",
          "tick" => mint_tick,
          "id" => "1",
          "amt" => "100"
        }

        expect_ethscription_success(
          create_input(
            creator: bob,
            to: dummy_recipient,
            data_uri: "data:," + mint_data.to_json
          )
        ) do |results|
          # Verify the ethscription was created
          ethscription_id = results[:ethscription_ids].first
          stored = get_ethscription_content(ethscription_id)

          expect(stored[:content]).to include('"op":"mint"')
          expect(stored[:content]).to include('"amt":"100"')

          token_state = get_token_state(mint_tick)
          expect(token_state).not_to be_nil
          expect(token_state[:totalMinted]).to eq(100)

          balance = get_token_balance(mint_tick, dummy_recipient)
          expect(balance).to eq(100)

          mint_item = get_mint_item(ethscription_id)
          expect(mint_item[:exists]).to eq(true)
          expect(mint_item[:amount]).to eq(100)
          expect(mint_item[:deployTxHash].downcase).to eq(token_state[:ethscriptionId].downcase)
        end
      end
    end  # end of "with shared token deployment" context

    it "handles sequential mints with incremental IDs" do
      # Deploy a separate token for this test to avoid conflicts
      tick = unique_tick('seqmint')

      deploy_data = {
        "p" => "erc-20",
        "op" => "deploy",
        "tick" => tick,  # Different token name
        "max" => "1000000",
        "lim" => "100"
      }

      deploy_results = import_l1_block([
        create_input(
          creator: alice,
          to: dummy_recipient,
          data_uri: "data:," + deploy_data.to_json
        )
      ], esip_overrides: {})

      expect(deploy_results[:l2_receipts].first[:status]).to eq('0x1'), "Token deployment should succeed"

      # First mint with ID 1
      mint1_data = {
        "p" => "erc-20",
        "op" => "mint",
        "tick" => tick,
        "id" => "1",
        "amt" => "100"
      }

      results1 = import_l1_block([
        create_input(
          creator: bob,
          to: dummy_recipient,
          data_uri: "data:," + mint1_data.to_json
        )
      ], esip_overrides: {})

      expect(results1[:l2_receipts].first[:status]).to eq('0x1'), "First mint should succeed"

      # Second mint with ID 2
      mint2_data = {
        "p" => "erc-20",
        "op" => "mint",
        "tick" => tick,
        "id" => "2",
        "amt" => "100"
      }

      results2 = import_l1_block([
        create_input(
          creator: bob,
          to: dummy_recipient,
          data_uri: "data:," + mint2_data.to_json
        )
      ], esip_overrides: {})

      expect(results2[:l2_receipts].first[:status]).to eq('0x1'), "Second mint should succeed"

      mint1_ethscription_id = results1[:ethscription_ids].first
      mint2_ethscription_id = results2[:ethscription_ids].first

      token_state = get_token_state(tick)
      expect(token_state[:totalMinted]).to eq(200)

      balance = get_token_balance(tick, dummy_recipient)
      expect(balance).to eq(200)  # 100 + 100

      mint_item1 = get_mint_item(mint1_ethscription_id)
      mint_item2 = get_mint_item(mint2_ethscription_id)

      [mint_item1, mint_item2].each do |mint_item|
        expect(mint_item[:exists]).to eq(true)
        expect(mint_item[:amount]).to eq(100)
        expect(mint_item[:deployTxHash].downcase).to eq(token_state[:ethscriptionId].downcase)
      end
    end

    it "rejects mint with duplicate ID" do
      # Deploy a separate token for this test
      tick = unique_tick('duptest')
      deploy_data = {
        "p" => "erc-20",
        "op" => "deploy",
        "tick" => tick,
        "max" => "1000000",
        "lim" => "100"
      }

      expect_ethscription_success(
        create_input(
          creator: alice,
          to: dummy_recipient,
          data_uri: "data:," + deploy_data.to_json
        )
      )

      mint_data = {
        "p" => "erc-20",
        "op" => "mint",
        "tick" => tick,
        "id" => "1",
        "amt" => "100"
      }

      # First mint succeeds
      expect_ethscription_success(
        create_input(
          creator: bob,
          to: dummy_recipient,
          data_uri: "data:," + mint_data.to_json
        )
      )

      # Second mint with same ID creates ethscription but protocol handler rejects
      expect_ethscription_failure(
        create_input(
          creator: charlie,
          to: dummy_recipient,
          data_uri: "data:," + mint_data.to_json
        ),
        reason: :revert
      )
    end
  end

  describe "Protocol Format Validation" do
    it "requires exact JSON format for token operations" do
      # Extra whitespace in JSON should fail
      tick = unique_tick('badformat')
      invalid_format = '{"p": "erc-20", "op": "deploy", "tick": "' + tick + '", "max": "100", "lim": "10"}'

      content_uri = "data:," + invalid_format

      expect_protocol_extraction_failure(
        create_input(
          creator: alice,
          to: dummy_recipient,
          data_uri: content_uri
        )
      ) do |results, stored|
        # The token regex requires exact format with no extra spaces
        expect(stored[:content]).to include('erc-20')

        token_params = ProtocolParser.for_calldata(content_uri)
        expect(token_params).to eq([''.b, ''.b, ''.b])
      end
    end

    it "requires lowercase ticks" do
      tick = unique_tick('uppertest').upcase
      uppercase_tick = {
        "p" => "erc-20",
        "op" => "deploy",
        "tick" => tick,  # Uppercase not allowed
        "max" => "1000",
        "lim" => "100"
      }

      expect_protocol_extraction_failure(
        create_input(
          creator: alice,
          to: dummy_recipient,
          data_uri: "data:," + uppercase_tick.to_json
        )
      )
    end

    it "limits tick length to 28 characters" do
      tick = unique_tick('toolongtick')
      long_tick = {
        "p" => "erc-20",
        "op" => "deploy",
        "tick" => tick + "a" * 29,  # Too long
        "max" => "1000",
        "lim" => "100"
      }

      expect_protocol_extraction_failure(
        create_input(
          creator: alice,
          to: dummy_recipient,
          data_uri: "data:," + long_tick.to_json
        )
      )
    end

    it "rejects negative numbers" do
      tick = unique_tick('negative')
      negative_max = {
        "p" => "erc-20",
        "op" => "deploy",
        "tick" => tick,
        "max" => "-1000",  # Negative not allowed
        "lim" => "100"
      }

      expect_protocol_extraction_failure(
        create_input(
          creator: alice,
          to: dummy_recipient,
          data_uri: "data:," + negative_max.to_json
        )
      )
    end

    it "rejects numbers with leading zeros" do
      tick = unique_tick('leadzero')
      leading_zero = {
        "p" => "erc-20",
        "op" => "mint",
        "tick" => tick,
        "id" => "01",  # Leading zero not allowed
        "amt" => "100"
      }

      expect_protocol_extraction_failure(
        create_input(
          creator: alice,
          to: dummy_recipient,
          data_uri: "data:," + leading_zero.to_json
        )
      )
    end
  end

  describe "Contract State Verification" do
    it "creates a token and verifies it exists in contract" do
      tick = unique_tick('verifytoken')
      token_data = {
        "p" => "erc-20",
        "op" => "deploy",
        "tick" => tick,
        "max" => "1000000",
        "lim" => "1000"
      }

      expect_ethscription_success(
        create_input(
          creator: alice,
          to: dummy_recipient,
          data_uri: "data:," + token_data.to_json
        )
      ) do |results|
        ethscription_id = results[:ethscription_ids].first

        token_state = get_token_state(tick)
        expect(token_state).not_to be_nil
        expect(token_state[:exists]).to eq(true)
        expect(token_state[:maxSupply]).to eq(1_000_000)
        expect(token_state[:mintLimit]).to eq(1000)
        expect(token_state[:totalMinted]).to eq(0)
        expect(token_state[:ethscriptionId].downcase).to eq(ethscription_id.downcase)
        expect(token_state[:tokenContract]).to match(/^0x[0-9a-fA-F]{40}$/)
        expect(token_state[:protocol]).to eq('erc-20-fixed-denomination')
      end
    end

    it "tracks mint count and enforces limits" do
      # Deploy with low limit for testing
      tick = unique_tick('limitedtoken')
      deploy_data = {
        "p" => "erc-20",
        "op" => "deploy",
        "tick" => tick,
        "max" => "300",
        "lim" => "100"
      }

      expect_ethscription_success(
        create_input(
          creator: alice,
          to: dummy_recipient,
          data_uri: "data:," + deploy_data.to_json
        )
      )

      mint_ethscription_ids = []

      # Mint up to limit
      [1, 2, 3].each do |i|
        mint_data = {
          "p" => "erc-20",
          "op" => "mint",
          "tick" => tick,
          "id" => i.to_s,
          "amt" => "100"
        }

        expect_ethscription_success(
          create_input(
            creator: bob,
            to: dummy_recipient,
            data_uri: "data:," + mint_data.to_json
          )
        ) do |results|
          mint_ethscription_ids << results[:ethscription_ids].first
        end
      end

      token_state = get_token_state(tick)
      expect(token_state[:totalMinted]).to eq(300)

      balance = get_token_balance(tick, dummy_recipient)
      expect(balance).to eq(300)

      mint_ethscription_ids.each do |mint_id|
        mint_item = get_mint_item(mint_id)
        expect(mint_item[:exists]).to eq(true)
        expect(mint_item[:amount]).to eq(100)
      end

      # Fourth mint should fail (exceeds max supply)
      mint_data = {
        "p" => "erc-20",
        "op" => "mint",
        "tick" => tick,
        "id" => "4",
        "amt" => "100"
      }

      expect_ethscription_success(
        create_input(
          creator: charlie,
          to: dummy_recipient,
          data_uri: "data:," + mint_data.to_json
        )
      ) do |results|
        failed_mint_id = results[:ethscription_ids].first
        mint_item = get_mint_item(failed_mint_id)
        expect(mint_item[:exists]).to eq(false)

        token_state = get_token_state(tick)
        expect(token_state[:totalMinted]).to eq(300)

        balance = get_token_balance(tick, dummy_recipient)
        expect(balance).to eq(300)
      end
    end
  end

  describe "End-to-End Token Workflow" do
    it "deploys token, mints tokens, and transfers via ethscription transfer" do
      # Step 1: Deploy token
      tick = unique_tick('flowtoken')
      deploy_data = {
        "p" => "erc-20",
        "op" => "deploy",
        "tick" => tick,
        "max" => "10000",
        "lim" => "500"
      }

      deploy_results = expect_ethscription_success(
        create_input(
          creator: alice,
          to: dummy_recipient,
          data_uri: "data:," + deploy_data.to_json
        )
      )

      deploy_ethscription_id = deploy_results[:ethscription_ids].first
      token_state = get_token_state(tick)
      expect(token_state).not_to be_nil
      expect(token_state[:exists]).to eq(true)
      expect(token_state[:maxSupply]).to eq(10_000)
      expect(token_state[:mintLimit]).to eq(500)
      expect(token_state[:totalMinted]).to eq(0)
      expect(token_state[:ethscriptionId].downcase).to eq(deploy_ethscription_id.downcase)
      expect(token_state[:tokenContract]).to match(/^0x[0-9a-fA-F]{40}$/)

      # Step 2: Mint tokens to Bob
      mint_data = {
        "p" => "erc-20",
        "op" => "mint",
        "tick" => tick,
        "id" => "1",
        "amt" => "500"
      }

      mint_results = expect_ethscription_success(
        create_input(
          creator: bob,
          to: bob,  # Mint to Bob so he owns the ethscription and can transfer it
          data_uri: "data:," + mint_data.to_json
        )
      )

      mint_ethscription_id = mint_results[:ethscription_ids].first

      token_state_after_mint = get_token_state(tick)
      expect(token_state_after_mint[:totalMinted]).to eq(500)

      balance = get_token_balance(tick, bob)
      expect(balance).to eq(500)

      mint_item = get_mint_item(mint_ethscription_id)
      expect(mint_item[:exists]).to eq(true)
      expect(mint_item[:amount]).to eq(500)
      expect(mint_item[:deployTxHash].downcase).to eq(token_state[:ethscriptionId].downcase)

      # Step 3: Transfer the mint ethscription (transfers the tokens)
      # When an erc-20 mint ethscription is transferred, it transfers the tokens
      expect_transfer_success(
        transfer_input(
          from: bob,
          to: charlie,
          id: mint_ethscription_id
        ),
        mint_ethscription_id,
        charlie
      ) do |results|
        bob_balance = get_token_balance(tick, bob)
        expect(bob_balance).to eq(0)

        charlie_balance = get_token_balance(tick, charlie)
        expect(charlie_balance).to eq(500)
      end
    end
  end

  # Helper methods for token protocol state verification
  private

  def get_token_state(tick)
    token = Erc20FixedDenominationReader.get_token(tick)
    return nil if token.nil?

    zero_address = '0x0000000000000000000000000000000000000000'

    {
      exists: token[:tokenContract] != zero_address,
      maxSupply: token[:maxSupply],
      mintLimit: token[:mintLimit],
      totalMinted: token[:totalMinted],
      tokenContract: token[:tokenContract],
      ethscriptionId: token[:ethscriptionId],
      protocol: token[:protocol],
      tick: token[:tick]
    }
  end

  def token_exists?(tick)
    Erc20FixedDenominationReader.token_exists?(tick)
  end

  def get_token_balance(tick, address)
    Erc20FixedDenominationReader.get_token_balance(tick, address)
  end

  def get_mint_item(ethscription_id)
    item = Erc20FixedDenominationReader.get_token_item(ethscription_id)

    zero_bytes32 = '0x0000000000000000000000000000000000000000000000000000000000000000'

    return {
      exists: false,
      amount: 0,
      deployTxHash: zero_bytes32,
      ethscriptionId: ethscription_id
    } if item.nil?

    {
      exists: item[:deployTxHash] != zero_bytes32,
      amount: item[:amount],
      deployTxHash: item[:deployTxHash],
      ethscriptionId: ethscription_id
    }
  end

  def unique_tick(base)
    suffix = SecureRandom.hex(4)
    tick = "#{base}#{suffix}".downcase
    tick[0, 28]
  end
end
