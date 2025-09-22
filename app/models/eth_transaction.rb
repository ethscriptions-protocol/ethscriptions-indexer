class EthTransaction < T::Struct
  include SysConfig
  
  # ESIP event signatures for detecting Ethscription events
  def self.event_signature(event_name)
    "0x" + Digest::Keccak256.hexdigest(event_name)
  end
  
  CreateEthscriptionEventSig = event_signature("ethscriptions_protocol_CreateEthscription(address,string)")
  Esip1EventSig = event_signature("ethscriptions_protocol_TransferEthscription(address,bytes32)")
  Esip2EventSig = event_signature("ethscriptions_protocol_TransferEthscriptionForPreviousOwner(address,address,bytes32)")
  
  const :block_hash, Hash32
  const :block_number, Integer
  const :block_timestamp, Integer
  const :tx_hash, Hash32
  const :transaction_index, Integer
  const :input, ByteString
  const :chain_id, T.nilable(Integer)
  const :from_address, Address20
  const :to_address, T.nilable(Address20)
  const :status, Integer
  const :logs, T::Array[T.untyped], default: []
  const :eth_block, T.nilable(EthBlock)
  const :ethscription_transactions, T::Array[EthscriptionTransaction], default: []

  # Alias for consistency with ethscription_detector
  sig { returns(Hash32) }
  def transaction_hash
    tx_hash
  end
  

  sig { params(block_result: T.untyped, receipt_result: T.untyped).returns(T::Array[EthTransaction]) }
  def self.from_rpc_result(block_result, receipt_result)
    block_hash = block_result['hash']
    block_number = block_result['number'].to_i(16)
    
    indexed_receipts = receipt_result.index_by{|el| el['transactionHash']}
    
    block_result['transactions'].map do |tx|
      current_receipt = indexed_receipts[tx['hash']]
      
      EthTransaction.new(
        block_hash: Hash32.from_hex(block_hash),
        block_number: block_number,
        block_timestamp: block_result['timestamp'].to_i(16),
        tx_hash: Hash32.from_hex(tx['hash']),
        transaction_index: tx['transactionIndex'].to_i(16),
        input: ByteString.from_hex(tx['input']),
        chain_id: tx['chainId']&.to_i(16),
        from_address: Address20.from_hex(tx['from']),
        to_address: tx['to'] ? Address20.from_hex(tx['to']) : nil,
        status: current_receipt['status'].to_i(16),
        logs: current_receipt['logs'],
      )
    end
  end
  
  sig { params(block_results: T.untyped, receipt_results: T.untyped, ethscriptions_block: EthscriptionsBlock).returns(T::Array[EthscriptionTransaction]) }
  def self.ethscription_txs_from_rpc_results(block_results, receipt_results, ethscriptions_block)
    eth_txs = from_rpc_result(block_results, receipt_results)

    # Collect all deposits from all transactions
    all_deposits = []
    eth_txs.sort_by(&:transaction_index).each do |eth_tx|
      next unless eth_tx.is_success?

      # Build deposits using the unified builder
      deposits = EthscriptionTransactionBuilder.build_deposits(eth_tx, ethscriptions_block)
      all_deposits.concat(deposits)
    end

    all_deposits
  end
  
  sig { returns(T::Boolean) }
  def is_success?
    status == 1
  end
  
  sig { returns(Hash32) }
  def ethscription_source_hash
    tx_hash
  end
end
