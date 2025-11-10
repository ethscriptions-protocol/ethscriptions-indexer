require 'rails_helper'

RSpec.describe WordDomainsParser do
  describe 'via ProtocolParser' do
    it 'parses raw word inscriptions' do
      params = ProtocolParser.for_calldata('data:,pizza')

      expect(params[0]).to eq('word-domains'.b)
      expect(params[1]).to eq('register'.b)
      decoded = Eth::Abi.decode(['string'], params[2])
      expect(decoded.first).to eq('pizza')
    end

    it 'rejects mixed-case words' do
      params = ProtocolParser.for_calldata('data:,Pizza')
      expect(params).to eq([''.b, ''.b, ''.b])
    end

    it 'rejects disallowed characters' do
      params = ProtocolParser.for_calldata('data:,hello.world')
      expect(params).to eq([''.b, ''.b, ''.b])
    end

    it 'parses JSON set_primary operations' do
      json = 'data:,{"p":"word-domains","op":"set_primary","name":"alpha"}'
      params = ProtocolParser.for_calldata(json)

      expect(params[0]).to eq('word-domains'.b)
      expect(params[1]).to eq('set_primary'.b)
      expect(Eth::Abi.decode(['string'], params[2]).first).to eq('alpha')
    end

    it 'allows clearing primary with empty string' do
      json = 'data:,{"p":"word-domains","op":"set_primary","name":""}'
      params = ProtocolParser.for_calldata(json)

      expect(params[1]).to eq('set_primary'.b)
      expect(Eth::Abi.decode(['string'], params[2]).first).to eq('')
    end

    it 'accepts 31 character names and rejects longer ones' do
      valid = 'a' * 30
      invalid = 'b' * 31

      expect(ProtocolParser.for_calldata("data:,#{valid}")[1]).to eq('register'.b)
      expect(ProtocolParser.for_calldata("data:,#{invalid}")).to eq([''.b, ''.b, ''.b])
    end
  end
end
