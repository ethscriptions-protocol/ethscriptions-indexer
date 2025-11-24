require 'rails_helper'

RSpec.describe ProtocolParser do
  let(:zero_merkle_root) { '0x' + '0' * 64 }

  describe '.extract' do
    context 'erc-20-fixed-denomination protocol' do
      it 'parses a valid deploy inscription' do
        content_uri = 'data:,{"p":"erc-20","op":"deploy","tick":"punk","max":"21000000","lim":"1000"}'

        result = described_class.extract(content_uri)

        expect(result).not_to be_nil
        expect(result[:type]).to eq(:erc20_fixed_denomination)
        expect(result[:protocol]).to eq('erc-20-fixed-denomination')
        expect(result[:operation]).to eq('deploy'.b)
      end

      it 'parses a valid mint inscription' do
        content_uri = 'data:,{"p":"erc-20","op":"mint","tick":"punk","id":"1","amt":"100"}'

        result = described_class.extract(content_uri)

        expect(result).not_to be_nil
        expect(result[:type]).to eq(:erc20_fixed_denomination)
        expect(result[:operation]).to eq('mint'.b)
      end

      it 'returns nil when the inscription is malformed' do
        content_uri = 'data:,{"p":"erc-20","op":"mint","tick":"punk","amt":"100"}'

        expect(described_class.extract(content_uri)).to be_nil
      end
    end

    context 'erc-721 collections protocol' do
      it 'parses a create_collection inscription' do
        content_uri = %(data:,{"p":"erc-721-ethscriptions-collection","op":"create_collection","name":"My NFTs","symbol":"MNFT","max_supply":"100","description":"","logo_image_uri":"","banner_image_uri":"","background_color":"","website_link":"","twitter_link":"","discord_link":"","merkle_root":"#{zero_merkle_root}","initial_owner":"0x0000000000000000000000000000000000000001"})

        result = described_class.extract(content_uri)

        expect(result).not_to be_nil
        expect(result[:type]).to eq(:erc721_ethscriptions_collection)
        expect(result[:protocol]).to eq('erc-721-ethscriptions-collection'.b)
        expect(result[:operation]).to eq('create_collection'.b)
      end

      it 'parses add_self_to_collection and succeeds with required fields' do
        inscription_id = '0x' + '1' * 64
        content_uri = 'data:,{"p":"erc-721-ethscriptions-collection","op":"add_self_to_collection","collection_id":"0x' + '2' * 64 + '","item":{"item_index":"0","name":"Item","background_color":"#000000","description":"","attributes":[],"merkle_proof":[]}}'

        result = described_class.extract(content_uri, ethscription_id: inscription_id)

        expect(result).not_to be_nil
        expect(result[:type]).to eq(:erc721_ethscriptions_collection)
        expect(result[:operation]).to eq('add_self_to_collection'.b)
      end

      it 'returns nil for non-collection JSON' do
        expect(described_class.extract('data:,{"p":"foo","op":"bar"}')).to be_nil
      end
    end

    context 'non-protocol data' do
      it 'returns nil for text payloads' do
        expect(described_class.extract('data:,Hello World')).to be_nil
      end

      it 'returns nil for invalid JSON' do
        expect(described_class.extract('data:,{invalid json')).to be_nil
      end

      it 'returns nil for nil input' do
        expect(described_class.extract(nil)).to be_nil
      end
    end
  end

  describe '.for_calldata' do
    it 'encodes erc-20 deploy params' do
      content_uri = 'data:,{"p":"erc-20","op":"deploy","tick":"punk","max":"21000000","lim":"1000"}'

      protocol, operation, encoded = described_class.for_calldata(content_uri)

      expect(protocol).to eq('erc-20-fixed-denomination'.b)
      expect(operation).to eq('deploy'.b)
      decoded = Eth::Abi.decode(['(string,uint256,uint256)'], encoded)[0]
      expect(decoded).to eq(['punk'.b, 21_000_000, 1000])
    end

    it 'encodes erc-20 mint params' do
      content_uri = 'data:,{"p":"erc-20","op":"mint","tick":"punk","id":"1","amt":"100"}'

      protocol, operation, encoded = described_class.for_calldata(content_uri)

      expect(protocol).to eq('erc-20-fixed-denomination'.b)
      expect(operation).to eq('mint'.b)
      decoded = Eth::Abi.decode(['(string,uint256,uint256)'], encoded)[0]
      expect(decoded).to eq(['punk'.b, 1, 100])
    end

    it 'returns encoded data for collections protocol' do
      content_uri = %(data:,{"p":"erc-721-ethscriptions-collection","op":"create_collection","name":"My NFTs","symbol":"MNFT","max_supply":"42","description":"","logo_image_uri":"","banner_image_uri":"","background_color":"","website_link":"","twitter_link":"","discord_link":"","merkle_root":"#{zero_merkle_root}","initial_owner":"0x0000000000000000000000000000000000000001"})

      protocol, operation, encoded = described_class.for_calldata(content_uri)

      expect(protocol).to eq('erc-721-ethscriptions-collection'.b)
      expect(operation).to eq('create_collection'.b)
      expect(encoded).not_to be_empty
    end

    it 'returns empty protocol params when nothing matches' do
      expect(described_class.for_calldata('data:,Hello World')).to eq([''.b, ''.b, ''.b])
    end
  end
end
