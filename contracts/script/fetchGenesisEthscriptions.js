#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

// Genesis blocks for mainnet
const GENESIS_BLOCKS = [
  1608625, 3369985, 3981254, 5873780, 8205613, 9046950,
  9046974, 9239285, 9430552, 10548855, 10711341, 15437996, 17478950
];

const API_BASE = 'https://api.ethscriptions.com/v2';
const OUTPUT_FILE = path.join(__dirname, 'genesisEthscriptions.json');

async function fetchWithRetry(url, retries = 3) {
  for (let i = 0; i < retries; i++) {
    try {
      const response = await fetch(url);
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`);
      }
      return await response.json();
    } catch (error) {
      console.error(`Attempt ${i + 1} failed for ${url}:`, error.message);
      if (i === retries - 1) throw error;
      // Wait before retrying (exponential backoff)
      await new Promise(resolve => setTimeout(resolve, 1000 * Math.pow(2, i)));
    }
  }
}

async function fetchEthscriptionsForBlock(blockNumber) {
  console.log(`Fetching ethscriptions for block ${blockNumber}...`);
  
  const url = `${API_BASE}/ethscriptions?block_number=${blockNumber}`;
  const data = await fetchWithRetry(url);
  
  if (data.result && Array.isArray(data.result)) {
    console.log(`  Found ${data.result.length} ethscriptions in block ${blockNumber}`);
    return data.result;
  }
  
  console.log(`  No ethscriptions found in block ${blockNumber}`);
  return [];
}

async function main() {
  console.log('Starting to fetch genesis ethscriptions...\n');
  
  const allEthscriptions = [];
  const blockData = {};
  
  for (const blockNumber of GENESIS_BLOCKS) {
    try {
      const ethscriptions = await fetchEthscriptionsForBlock(blockNumber);
      
      if (ethscriptions.length > 0) {
        // Store ethscriptions with their block data
        for (const ethscription of ethscriptions) {
          allEthscriptions.push({
            ...ethscription,
            // Add genesis-specific data
            genesis_block: blockNumber,
            is_genesis: true
          });
        }
        
        // Store block metadata
        if (ethscriptions.length > 0 && ethscriptions[0].block_timestamp) {
          blockData[blockNumber] = {
            blockNumber: blockNumber,
            blockHash: ethscriptions[0].block_blockhash,
            timestamp: ethscriptions[0].block_timestamp,
            ethscriptionCount: ethscriptions.length
          };
        }
      }
      
      // Small delay to avoid rate limiting
      await new Promise(resolve => setTimeout(resolve, 500));
      
    } catch (error) {
      console.error(`Failed to fetch block ${blockNumber}:`, error);
    }
  }
  
  console.log(`\nTotal ethscriptions found: ${allEthscriptions.length}`);
  
  // Sort by ethscription number
  allEthscriptions.sort((a, b) => {
    const numA = parseInt(a.ethscription_number);
    const numB = parseInt(b.ethscription_number);
    return numA - numB;
  });
  
  // Prepare output
  const output = {
    metadata: {
      totalCount: allEthscriptions.length,
      genesisBlocks: GENESIS_BLOCKS,
      blockData: blockData,
      fetchedAt: new Date().toISOString()
    },
    ethscriptions: allEthscriptions
  };
  
  // Write to file
  fs.writeFileSync(OUTPUT_FILE, JSON.stringify(output, null, 2));
  console.log(`\nData saved to ${OUTPUT_FILE}`);
  
  // Print summary
  console.log('\nSummary by block:');
  for (const [block, data] of Object.entries(blockData)) {
    console.log(`  Block ${block}: ${data.ethscriptionCount} ethscriptions`);
  }
}

// Run the script
main().catch(error => {
  console.error('Fatal error:', error);
  process.exit(1);
});