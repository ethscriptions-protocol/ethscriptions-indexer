require 'spec_helper'
require_relative '../../config/environment'

RSpec.describe EthscriptionDetector, type: :model do
  # Skip database setup for this test
  before(:all) do
    ActiveRecord::Base.remove_connection if ActiveRecord::Base.connected?
  end
  # Helper to create mock transaction
  def create_tx(attrs = {})
    defaults = {
      status: 1,
      block_number: 18_000_000,
      from_address: Address20.from_hex('0x1234567890123456789012345678901234567890'),
      to_address: Address20.from_hex('0xabcdefabcdefabcdefabcdefabcdefabcdefabcd'),
      transaction_hash: Hash32.from_hex('0x' + '9' * 64),
      input: ByteString.new(''.b),
      logs: nil
    }
    OpenStruct.new(defaults.merge(attrs))
  end

  describe 'creation detection' do
    it 'detects creation from valid data URI input' do
      data_uri = "data:text/plain,Hello%20World"
      tx = create_tx(input: ByteString.new(data_uri.b))

      detector = described_class.new(tx)

      expect(detector.operations.length).to eq(1)
      expect(detector.operations.first[:type]).to eq(:create)
      expect(detector.operations.first[:content_uri]).to eq(data_uri)
    end

    it 'ignores invalid data URIs' do
      tx = create_tx(input: ByteString.new("not a data uri".b))

      detector = described_class.new(tx)

      expect(detector.operations).to be_empty
    end
  end

  describe 'transfer detection' do
    it 'detects single transfer without ESIP-5' do
      allow(SysConfig).to receive(:esip5_enabled?).and_return(false)

      ethscription_id = 'a' * 64
      tx = create_tx(input: ByteString.new([ethscription_id].pack('H*')))

      detector = described_class.new(tx)

      expect(detector.operations.length).to eq(1)
      expect(detector.operations.first[:type]).to eq(:transfer)
      expect(detector.operations.first[:ethscription_id]).to eq('0x' + ethscription_id)
    end

    it 'rejects multi-transfers without ESIP-5' do
      allow(SysConfig).to receive(:esip5_enabled?).and_return(false)

      tx = create_tx(input: ByteString.new(['a' * 64 + 'b' * 64].pack('H*')))

      detector = described_class.new(tx)

      expect(detector.operations).to be_empty
    end

    it 'detects multi-transfers with ESIP-5' do
      allow(SysConfig).to receive(:esip5_enabled?).and_return(true)

      ids = ['a' * 64, 'b' * 64, 'c' * 64]
      tx = create_tx(input: ByteString.new([ids.join].pack('H*')))

      detector = described_class.new(tx)

      expect(detector.operations.length).to eq(3)
      detector.operations.each_with_index do |op, i|
        expect(op[:type]).to eq(:transfer)
        expect(op[:transfer_index]).to eq(i)
      end
    end
  end

  describe 'event transfers' do
    it 'detects ESIP-1 transfers with contract as from' do
      allow(SysConfig).to receive(:esip1_enabled?).and_return(true)

      contract_addr = '0xc0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0'
      to_addr = '0xdestdestdestdestdestdestdestdestdestdest'

      event = {
        'removed' => false,
        'address' => contract_addr,
        'topics' => [
          described_class::ESIP1_SIG,
          '0x' + '0' * 24 + to_addr[2..],
          '0x' + 'f' * 64
        ],
        'logIndex' => '0x5'
      }

      tx = create_tx(logs: [event])
      detector = described_class.new(tx)

      expect(detector.operations.length).to eq(1)
      op = detector.operations.first
      expect(op[:type]).to eq(:transfer)
      expect(op[:from]).to eq(contract_addr)  # Contract address, not tx sender
      expect(op[:event_log_index]).to eq(5)
    end

    it 'skips events with wrong topic count' do
      allow(SysConfig).to receive(:esip1_enabled?).and_return(true)

      bad_event = {
        'removed' => false,
        'address' => '0xc0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0',
        'topics' => [
          described_class::ESIP1_SIG,
          '0x' + '0' * 64,
          '0x' + '0' * 64,
          '0x' + '0' * 64  # Extra topic - should have 3 not 4
        ],
        'logIndex' => '0x0'
      }

      tx = create_tx(logs: [bad_event])
      detector = described_class.new(tx)

      expect(detector.operations).to be_empty
    end

    it 'filters removed events' do
      allow(SysConfig).to receive(:esip1_enabled?).and_return(true)

      removed_event = {
        'removed' => true,  # This event was removed
        'address' => '0xc0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0',
        'topics' => [
          described_class::ESIP1_SIG,
          '0x' + '0' * 64,
          '0x' + '0' * 64
        ],
        'logIndex' => '0x0'
      }

      tx = create_tx(logs: [removed_event])
      detector = described_class.new(tx)

      expect(detector.operations).to be_empty
    end

    it 'processes events in order by logIndex' do
      allow(SysConfig).to receive(:esip1_enabled?).and_return(true)

      # Create events out of order
      events = [2, 1, 0].map do |idx|
        {
          'removed' => false,
          'address' => '0xc0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0',
          'topics' => [
            described_class::ESIP1_SIG,
            '0x' + '0' * 24 + 'beef' * 10,
            '0x' + idx.to_s * 64
          ],
          'logIndex' => idx.to_s(16)
        }
      end

      tx = create_tx(logs: events)
      detector = described_class.new(tx)

      expect(detector.operations.length).to eq(3)
      expect(detector.operations.map { |op| op[:event_log_index] }).to eq([0, 1, 2])
    end
  end

  describe 'failed transactions' do
    it 'ignores operations from failed transactions' do
      tx = create_tx(
        status: 0,  # Failed
        input: ByteString.new("data:text/plain,Failed".b)
      )

      detector = described_class.new(tx)

      expect(detector.operations).to be_empty
    end
  end

  describe 'normalization' do
    it 'normalizes addresses and hashes to lowercase' do
      tx = create_tx(
        from_address: Address20.from_hex('0xABCDEF' + '0' * 34),
        to_address: Address20.from_hex('0xFEDCBA' + '0' * 34),
        input: ByteString.new(['AABBCC' + 'DD' * 29].pack('H*'))
      )

      detector = described_class.new(tx)

      expect(detector.operations.length).to eq(1)
      op = detector.operations.first
      expect(op[:from]).to eq('0xabcdef' + '0' * 34)
      expect(op[:to]).to eq('0xfedcba' + '0' * 34)
      expect(op[:ethscription_id]).to eq('0xaabbcc' + 'dd' * 29)
    end
  end

  describe 'deduplication' do
    it 'deduplicates multiple create operations for same transaction' do
      allow(SysConfig).to receive(:esip3_enabled?).and_return(true)

      data_uri = "data:text/plain,Duplicate"

      create_event = {
        'removed' => false,
        'address' => '0xc0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0',
        'topics' => [
          described_class::CREATE_SIG,
          '0x' + '0' * 24 + 'beef' * 10
        ],
        'data' => Eth::Abi.encode(['string'], [data_uri]),
        'logIndex' => '0x0'
      }

      tx = create_tx(
        input: ByteString.new(data_uri.b),
        logs: [create_event]
      )

      detector = described_class.new(tx)

      # Should only have one create despite both input and event
      expect(detector.operations.length).to eq(1)
      expect(detector.operations.first[:type]).to eq(:create)
    end
  end
end