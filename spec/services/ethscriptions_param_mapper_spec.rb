require 'rails_helper'

RSpec.describe EthscriptionsParamMapper do
  let(:eth_transaction) do
    instance_double(
      EthTransaction,
      transaction_hash: "0x" + "a" * 64,
      from_address: "0x" + "b" * 40,
      to_address: "0x" + "c" * 40,
      block_number: 123456,
      transaction_index: 42,
      block_timestamp: 1234567890,
      utf8_input: "data:text/plain,Hello%20World"
    )
  end
  
  describe '.build_create_params' do
    it 'builds correct parameters for plain text data URI' do
      params = described_class.build_create_params(
        eth_transaction,
        creator: "0x" + "d" * 40,
        initial_owner: "0x" + "e" * 40,
        content_uri: "data:text/plain,Hello"
      )
      
      expect(params).to eq({
        transactionHash: eth_transaction.transaction_hash,
        initialOwner: "0x" + "e" * 40,
        contentUri: "data:text/plain,Hello".force_encoding('BINARY'),
        mimetype: "text/plain",
        mediaType: "text",
        mimeSubtype: "plain",
        esip6: false
      })
    end
    
    it 'handles base64 encoded data URI' do
      params = described_class.build_create_params(
        eth_transaction,
        creator: "0x" + "d" * 40,
        initial_owner: "0x" + "e" * 40,
        content_uri: "data:image/png;base64,iVBORw0KGgo"
      )
      
      expect(params).to include(
        mimetype: "image/png",
        mediaType: "image",
        mimeSubtype: "png",
        esip6: false
      )
    end
    
    it 'detects ESIP6 data URIs' do
      # Mock DataUri.esip6? to return true for this test
      allow(DataUri).to receive(:esip6?).and_return(true)
      
      params = described_class.build_create_params(
        eth_transaction,
        creator: "0x" + "d" * 40,
        initial_owner: "0x" + "e" * 40,
        content_uri: "data:,duplicate"
      )
      
      expect(params[:esip6]).to be true
    end
    
    it 'truncates long mimetypes' do
      long_mimetype = "application/" + "x" * 1000
      params = described_class.build_create_params(
        eth_transaction,
        creator: "0x" + "d" * 40,
        initial_owner: "0x" + "e" * 40,
        content_uri: "data:#{long_mimetype},content"
      )
      
      expect(params[:mimetype].length).to eq(1000)
    end
    
    it 'handles invalid data URIs gracefully' do
      params = described_class.build_create_params(
        eth_transaction,
        creator: "0x" + "d" * 40,
        initial_owner: "0x" + "e" * 40,
        content_uri: "not-a-data-uri"
      )
      
      expect(params).to include(
        mimetype: "",
        mediaType: "",
        mimeSubtype: "",
        esip6: false
      )
    end
  end
  
  describe '.build_create_params_from_input' do
    it 'uses transaction from and to addresses' do
      params = described_class.build_create_params_from_input(eth_transaction)
      
      expect(params).to include(
        transactionHash: eth_transaction.transaction_hash,
        initialOwner: eth_transaction.to_address.downcase,
        contentUri: eth_transaction.utf8_input.force_encoding('BINARY')
      )
    end
  end
  
  describe '.build_create_params_from_event' do
    let(:event_log) do
      {
        'address' => "0x" + "f" * 40,
        'topics' => [
          "0xevent_sig",
          "0x" + "0" * 24 + "1" * 40  # Padded address
        ],
        'data' => "0x" + "0" * 63 + "5" + # Offset (32 bytes)
                  "0" * 63 + "5" +         # Length (32 bytes)  
                  "48656c6c6f"              # "Hello" in hex
      }
    end
    
    it 'decodes event parameters correctly' do
      allow(HexDataProcessor).to receive(:clean_utf8).and_return("data:,Hello")
      
      params = described_class.build_create_params_from_event(
        eth_transaction,
        event_log
      )
      
      expect(params).to include(
        transactionHash: eth_transaction.transaction_hash,
        initialOwner: "0x" + "1" * 40,
        contentUri: "data:,Hello".force_encoding('BINARY')
      )
    end
  end
  
  describe '.build_transfer_params' do
    it 'builds correct transfer parameters' do
      params = described_class.build_transfer_params(
        ethscription_tx_hash: "0x" + "2" * 64,
        to_address: "0x" + "3" * 40
      )
      
      expect(params).to eq({
        transactionHash: "0x" + "2" * 64,
        to: "0x" + "3" * 40
      })
    end
  end
  
  describe '.build_tx_meta' do
    it 'builds transaction metadata' do
      meta = described_class.build_tx_meta(eth_transaction)
      
      expect(meta).to eq({
        from_address: eth_transaction.from_address.downcase,
        block_number: eth_transaction.block_number,
        transaction_index: eth_transaction.transaction_index,
        transaction_hash: eth_transaction.transaction_hash,
        block_timestamp: eth_transaction.block_timestamp
      })
    end
    
    it 'allows overriding from_address' do
      override_address = "0x" + "4" * 40
      meta = described_class.build_tx_meta(eth_transaction, from_address: override_address)
      
      expect(meta[:from_address]).to eq(override_address.downcase)
    end
  end
  
  describe '.validate_params' do
    context 'createEthscription validation' do
      let(:valid_params) do
        {
          transactionHash: "0x" + "5" * 64,
          initialOwner: "0x" + "6" * 40,
          contentUri: "data:,test"
        }
      end
      
      it 'returns empty array for valid params' do
        errors = described_class.validate_params(valid_params, :createEthscription)
        expect(errors).to be_empty
      end
      
      it 'detects missing transactionHash' do
        params = valid_params.except(:transactionHash)
        errors = described_class.validate_params(params, :createEthscription)
        expect(errors).to include("Missing transactionHash")
      end
      
      it 'detects missing initialOwner' do
        params = valid_params.except(:initialOwner)
        errors = described_class.validate_params(params, :createEthscription)
        expect(errors).to include("Missing initialOwner")
      end
      
      it 'detects missing contentUri' do
        params = valid_params.except(:contentUri)
        errors = described_class.validate_params(params, :createEthscription)
        expect(errors).to include("Missing contentUri")
      end
      
      it 'detects zero address' do
        params = valid_params.merge(initialOwner: "0x" + "0" * 40)
        errors = described_class.validate_params(params, :createEthscription)
        expect(errors).to include("Invalid initialOwner (zero address)")
      end
      
      it 'detects invalid data URI' do
        params = valid_params.merge(contentUri: "not-a-data-uri")
        errors = described_class.validate_params(params, :createEthscription)
        expect(errors).to include("Invalid contentUri (not a data URI)")
      end
    end
    
    context 'transferEthscription validation' do
      let(:valid_params) do
        {
          transactionHash: "0x" + "7" * 64,
          to: "0x" + "8" * 40
        }
      end
      
      it 'returns empty array for valid params' do
        errors = described_class.validate_params(valid_params, :transferEthscription)
        expect(errors).to be_empty
      end
      
      it 'detects missing transactionHash' do
        params = valid_params.except(:transactionHash)
        errors = described_class.validate_params(params, :transferEthscription)
        expect(errors).to include("Missing transactionHash")
      end
      
      it 'detects missing to address' do
        params = valid_params.except(:to)
        errors = described_class.validate_params(params, :transferEthscription)
        expect(errors).to include("Missing to address")
      end
      
      it 'detects zero address' do
        params = valid_params.merge(to: "0x" + "0" * 40)
        errors = described_class.validate_params(params, :transferEthscription)
        expect(errors).to include("Invalid to address (zero address)")
      end
    end
  end
end