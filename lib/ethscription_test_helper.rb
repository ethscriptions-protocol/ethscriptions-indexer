module EthscriptionTestHelper
  def self.create_from_hash(hash)
    client = EthBlock.rpc_client
    resp = client.send(:query_api,
      method: 'eth_getTransactionByHash',
      params: [hash]
    )['result']

    resp2 = client.send(:query_api,
      method: 'eth_getTransactionReceipt',
      params: [hash]
    )['result']
    
    create_eth_transaction(
      input: resp['input'],
      to: resp['to'],
      from: resp['from'],
      logs: resp2['logs']
    )
  end
  
  def self.create_eth_transaction(
    input:,
    from:,
    to:,
    logs: [],
    tx_hash: nil
  )
    existing = Ethscription.newest_first.first
    
    block_number = EthBlock.next_block_to_import
    
    transaction_index = existing&.transaction_index.to_i + 1
    overall_order_number = block_number * 1e8 + transaction_index
    
    hex_input = if input.match?(/\A0x([a-f0-9]{2})+\z/i)
      input.downcase
    else
      "0x" + input.bytes.map { |byte| byte.to_s(16).rjust(2, '0') }.join
    end
    
    if EthBlock.exists?
      parent_block = EthBlock.order(block_number: :desc).first
      parent_hash = parent_block.blockhash
    else
      parent_hash = "0x" + SecureRandom.hex(32)
    end
    
    eth_block = EthBlock.create!(
      block_number: block_number,
      blockhash: "0x" + SecureRandom.hex(32),
      parent_blockhash: parent_hash,
      timestamp: parent_block&.timestamp.to_i + 12,
      is_genesis_block: EthBlock.genesis_blocks.include?(block_number)
    )
    
    tx = EthTransaction.create!(
      block_number: block_number,
      block_timestamp: eth_block.timestamp,
      transaction_hash: tx_hash || "0x" + SecureRandom.hex(32),
      block_blockhash: eth_block.blockhash,
      from_address: from.downcase,
      to_address: to.downcase,
      transaction_index: transaction_index,
      input: hex_input,
      status: (block_number <= 4370000 ? nil : 1),
      logs: logs,
      gas_price: 1,
      gas_used: 1,
      transaction_fee: 1,
      value: 1,
    )
    
    tx.process!
    Token.process_block(eth_block)
    eth_block.update!(imported_at: Time.current)
    tx
  end
  
  def self.t
    create_eth_transaction(
      input: "data:,lksdjfkldsajlfdjskfs",
      from: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      to: "0xC2172a6315c1D7f6855768F843c420EbB36eDa97",
      logs: []
    )
  end
end
$et = EthscriptionTestHelper