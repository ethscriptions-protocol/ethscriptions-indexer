#!/usr/bin/env node

const { createPublicClient, http, parseAbiItem, getContract } = require('viem');
const { mainnet } = require('viem/chains');

// Contract addresses
const ETHSCRIPTIONS_CONTRACT = '0x3300000000000000000000000000000000000001';
const SYSTEM_ADDRESS = '0xdeaddeaddeaddeaddeaddeaddeaddeaddead0001';

// L1 genesis block from env
const L1_GENESIS_BLOCK = 17478949;

// Ethscriptions contract ABI (just the functions we need)
const ETHSCRIPTIONS_ABI = [
  {
    name: 'getEthscription',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'transactionHash', type: 'bytes32' }],
    outputs: [{
      name: '',
      type: 'tuple',
      components: [
        { name: 'contentSha', type: 'bytes32' },
        { name: 'creator', type: 'address' },
        { name: 'initialOwner', type: 'address' },
        { name: 'previousOwner', type: 'address' },
        { name: 'ethscriptionNumber', type: 'uint256' },
        { name: 'mimetype', type: 'string' },
        { name: 'mediaType', type: 'string' },
        { name: 'mimeSubtype', type: 'string' },
        { name: 'esip6', type: 'bool' },
        { name: 'isCompressed', type: 'bool' },
        { name: 'createdAt', type: 'uint256' },
        { name: 'l1BlockNumber', type: 'uint64' },
        { name: 'l2BlockNumber', type: 'uint64' },
        { name: 'l1BlockHash', type: 'bytes32' }
      ]
    }]
  }
];

// Create L2 client
const l2Client = createPublicClient({
  chain: {
    id: 0xeeee,
    name: 'Ethscriptions L2',
    network: 'ethscriptions-l2',
    rpcUrls: {
      default: { http: ['http://localhost:8545'] }
    }
  },
  transport: http('http://localhost:8545')
});

// Get Ethscriptions contract
const ethscriptionsContract = getContract({
  address: ETHSCRIPTIONS_CONTRACT,
  abi: ETHSCRIPTIONS_ABI,
  client: l2Client
});

async function fetchL1Ethscriptions(blockNumber) {
  const response = await fetch(
    `https://api.ethscriptions.com/v2/ethscriptions?block_number=${blockNumber}&per_page=100`
  );
  const data = await response.json();
  return data.result || [];
}

async function getL2BlockForL1(l1BlockNumber) {
  if (l1BlockNumber < L1_GENESIS_BLOCK) return null;
  if (l1BlockNumber === L1_GENESIS_BLOCK) return 0n;
  
  const l2BlockNumber = BigInt(l1BlockNumber - L1_GENESIS_BLOCK);
  
  // Verify block exists
  try {
    const block = await l2Client.getBlock({ blockNumber: l2BlockNumber });
    return block ? l2BlockNumber : null;
  } catch (e) {
    return null;
  }
}

async function getL2Ethscription(txHash) {
  try {
    // Ensure txHash is properly formatted as bytes32 (0x-prefixed)
    const formattedHash = txHash.startsWith('0x') ? txHash : `0x${txHash}`;
    
    console.log(`  Calling getEthscription(${formattedHash.slice(0, 10)}...)`);
    
    const result = await ethscriptionsContract.read.getEthscription([formattedHash]);
    
    return {
      creator: result.creator.toLowerCase(),
      initialOwner: result.initialOwner.toLowerCase(),
      contentSha: result.contentSha,
      mimetype: result.mimetype,
      l1BlockNumber: Number(result.l1BlockNumber),
      l2BlockNumber: Number(result.l2BlockNumber)
    };
  } catch (error) {
    console.log(`  Error calling contract: ${error.message}`);
    return null;
  }
}

async function verifyBlock(l1BlockNumber) {
  console.log('='.repeat(80));
  console.log(`Verifying Ethscriptions for L1 block ${l1BlockNumber}`);
  console.log('='.repeat(80));
  
  // Get Ethscriptions from L1 API
  const l1Ethscriptions = await fetchL1Ethscriptions(l1BlockNumber);
  console.log(`\n📦 L1 API: Found ${l1Ethscriptions.length} Ethscription(s)`);
  
  if (l1Ethscriptions.length === 0) {
    console.log('No Ethscriptions to verify in this block');
    return true;
  }
  
  // Get L2 block number
  const l2BlockNumber = await getL2BlockForL1(l1BlockNumber);
  
  if (l2BlockNumber === null) {
    console.log(`❌ L1 block ${l1BlockNumber} not yet imported to L2`);
    return false;
  }
  
  console.log(`📋 L2 block number: ${l2BlockNumber}`);
  
  // Get transactions from L2 block
  const l2Block = await l2Client.getBlock({ 
    blockNumber: l2BlockNumber,
    includeTransactions: true 
  });
  
  // Filter for Ethscription creation transactions
  const ethscriptionTxs = l2Block.transactions.filter(tx => 
    tx.to?.toLowerCase() === ETHSCRIPTIONS_CONTRACT.toLowerCase() &&
    tx.from?.toLowerCase() !== SYSTEM_ADDRESS.toLowerCase()
  );
  
  console.log(`📋 L2: Found ${ethscriptionTxs.length} Ethscription transaction(s)`);
  
  // Compare counts
  if (l1Ethscriptions.length !== ethscriptionTxs.length) {
    console.log(`❌ Count mismatch! L1: ${l1Ethscriptions.length}, L2: ${ethscriptionTxs.length}`);
    return false;
  }
  
  // Verify each Ethscription
  let allMatch = true;
  
  for (let i = 0; i < l1Ethscriptions.length; i++) {
    const l1Etsc = l1Ethscriptions[i];
    console.log(`\n[${i+1}/${l1Ethscriptions.length}] Verifying Ethscription ${l1Etsc.transaction_hash.slice(0, 10)}...`);
    
    // Get Ethscription from L2 contract
    const l2Etsc = await getL2Ethscription(l1Etsc.transaction_hash);
    
    if (!l2Etsc) {
      console.log('  ❌ Not found on L2!');
      allMatch = false;
      continue;
    }
    
    let matches = true;
    
    // Check creator
    if (l2Etsc.creator !== l1Etsc.creator.toLowerCase()) {
      console.log(`  ❌ Creator mismatch: L1=${l1Etsc.creator}, L2=${l2Etsc.creator}`);
      matches = false;
    }
    
    // Check initial owner
    const expectedOwner = (l1Etsc.initial_owner || l1Etsc.creator).toLowerCase();
    if (l2Etsc.initialOwner !== expectedOwner) {
      console.log(`  ❌ Initial owner mismatch: L1=${expectedOwner}, L2=${l2Etsc.initialOwner}`);
      matches = false;
    }
    
    // Check mimetype
    if (l2Etsc.mimetype !== l1Etsc.mimetype) {
      console.log(`  ❌ Mimetype mismatch: L1=${l1Etsc.mimetype}, L2=${l2Etsc.mimetype}`);
      matches = false;
    }
    
    // Check L1 block number
    if (l2Etsc.l1BlockNumber !== l1BlockNumber) {
      console.log(`  ❌ L1 block mismatch: Expected=${l1BlockNumber}, L2=${l2Etsc.l1BlockNumber}`);
      matches = false;
    }
    
    if (matches) {
      console.log('  ✅ All fields match!');
    } else {
      allMatch = false;
    }
  }
  
  console.log('\n' + '='.repeat(80));
  if (allMatch) {
    console.log('✅ SUCCESS: All Ethscriptions verified!');
  } else {
    console.log('❌ FAILURE: Some Ethscriptions did not match');
  }
  console.log('='.repeat(80));
  
  return allMatch;
}

// Main
async function main() {
  const l1Block = process.argv[2] ? parseInt(process.argv[2]) : 17478950;
  
  try {
    await verifyBlock(l1Block);
  } catch (error) {
    console.error('Error:', error);
    process.exit(1);
  }
}

main();