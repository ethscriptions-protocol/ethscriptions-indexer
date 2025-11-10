require 'rails_helper'

RSpec.describe "EthscriptionTransactionBuilder" do
  describe 'ERC-20 protocol parsing via ProtocolParser' do
    it 'extracts deploy operation params' do
      content_uri = 'data:,{"p":"erc-20","op":"deploy","tick":"eths","max":"21000000","lim":"1000"}'

      params = ProtocolParser.for_calldata(content_uri)

      expect(params[0]).to eq('erc-20-fixed-denomination'.b)
      expect(params[1]).to eq('deploy'.b)
      # params[2] is ABI-encoded (string, uint256, uint256)
      decoded = Eth::Abi.decode(['(string,uint256,uint256)'], params[2])[0]
      expect(decoded).to eq(['eths', 21000000, 1000])
    end

    it 'extracts mint operation params' do
      content_uri = 'data:,{"p":"erc-20","op":"mint","tick":"eths","id":"1","amt":"1000"}'

      params = ProtocolParser.for_calldata(content_uri)

      expect(params[0]).to eq('erc-20-fixed-denomination'.b)
      expect(params[1]).to eq('mint'.b)
      decoded = Eth::Abi.decode(['(string,uint256,uint256)'], params[2])[0]
      expect(decoded).to eq(['eths', 1, 1000])
    end

    it 'returns default params for non-token content' do
      content_uri = 'data:,Hello World!'

      params = ProtocolParser.for_calldata(content_uri)

      expect(params).to eq([''.b, ''.b, ''.b])
    end

    it 'returns default params for invalid JSON' do
      content_uri = 'data:,{invalid json'

      params = ProtocolParser.for_calldata(content_uri)

      expect(params).to eq([''.b, ''.b, ''.b])
    end

    it 'handles unknown operations with protocol/tick' do
      content_uri = 'data:,{"p":"new-proto","op":"custom","tick":"test"}'

      params = ProtocolParser.for_calldata(content_uri)

      expect(params).to eq([''.b, ''.b, ''.b])
    end
  end
end
