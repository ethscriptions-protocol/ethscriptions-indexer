require 'swagger_helper'

RSpec.describe 'Ethscriptions API', doc: true do
  path '/ethscriptions' do
    get 'List Ethscriptions' do
      tags 'Ethscriptions'
      operationId 'listEthscriptions'
      produces 'application/json'
      description <<~DESC
        Retrieves a list of ethscriptions, supporting various filters. 
        By default, the results limit is set to 100.
        
        - If `transaction_hash_only` is set to true, the results limit increases to 1000.
        - If `include_latest_transfer` is set to true, the results limit is reduced to 50.
        
        The filter parameters below can be either individual values or arrays of values.
      DESC
      
      parameter name: :current_owner, in: :query, type: :string, description: 'Filter by current owner address'
      parameter name: :creator, in: :query, type: :string, description: 'Filter by creator address'
      parameter name: :initial_owner, in: :query, type: :string, description: 'Filter by initial owner address'
      parameter name: :previous_owner, in: :query, type: :string, description: 'Filter by previous owner address'
      parameter name: :mimetype, in: :query, type: :string, description: 'Filter by MIME type'
      parameter name: :media_type, in: :query, type: :string, description: 'Filter by media type'
      parameter name: :mime_subtype, in: :query, type: :string, description: 'Filter by MIME subtype'
      parameter name: :content_sha, in: :query, type: :string, description: 'Filter by content SHA hash'
      parameter name: :transaction_hash, in: :query, type: :string, description: 'Filter by Ethereum transaction hash'
      parameter name: :block_number, in: :query, type: :string, description: 'Filter by block number'
      parameter name: :block_timestamp, in: :query, type: :string, description: 'Filter by block timestamp'
      parameter name: :block_blockhash, in: :query, type: :string, description: 'Filter by block hash'
      parameter name: :ethscription_number, in: :query, type: :string, description: 'Filter by ethscription number'
      parameter name: :attachment_sha, in: :query, type: :string, description: 'Filter by attachment SHA hash'
      parameter name: :attachment_content_type, in: :query, type: :string, description: 'Filter by attachment content type'
      parameter name: :attachment_present, in: :query, type: :string, description: 'Filter by presence of an attachment', enum: ['true', 'false']
      parameter name: :token_tick, in: :query, type: :string, description: 'Filter by token tick', example: "eths"
      parameter name: :token_protocol, in: :query, type: :string, description: 'Filter by token protocol', example: "erc-20"
      parameter name: :transferred_in_tx, in: :query, type: :string, description: 'Filter by transfer transaction hash'
      
      parameter name: :after_block, 
                in: :query, 
                type: :integer, 
                description: 'Filter by block number, returning only ethscriptions after the specified block.',
                required: false

      parameter name: :before_block, 
                in: :query, 
                type: :integer, 
                description: 'Filter by block number, returning only ethscriptions before the specified block.',
                required: false
      
      parameter name: :transaction_hash_only, 
                in: :query, 
                type: :boolean, 
                description: 'Return only transaction hashes. When set to true, increases results limit to 1000.',
                required: false

      parameter name: :include_latest_transfer, 
                in: :query, 
                type: :boolean, 
                description: 'Include latest transfer information. When set to true, reduces results limit to 50.',
                required: false


      # Include common pagination parameters
      parameter ApiCommonParameters.sort_by_parameter
      parameter ApiCommonParameters.reverse_parameter
      parameter ApiCommonParameters.max_results_parameter
      parameter ApiCommonParameters.page_key_parameter

      response '200', 'ethscriptions list' do
        schema type: :object,
               properties: {
                 result: {
                   type: :array,
                   items: { '$ref' => '#/components/schemas/Ethscription' }
                 },
                 pagination: { '$ref' => '#/components/schemas/PaginationObject' }
               },
               description: 'A list of ethscriptions based on filter criteria.'

        run_test!
      end
    end
  end
  
  path '/ethscriptions/{tx_hash_or_ethscription_number}' do
    get 'Show Ethscription' do
      tags 'Ethscriptions'
      operationId 'getEthscriptionByTransactionHash'
      produces 'application/json'
      description 'Retrieves an ethscription, including its transfers, by its transaction hash.'
      parameter name: :tx_hash_or_ethscription_number,
                in: :path,
                type: :string,
                description: 'Transaction hash or ethscription number of the ethscription',
                example: "0x0ef100873db4e3b7446e9a3be0432ab8bc92119d009aa200f70c210ac9dcd4a6",
                required: true
                
      response '200', 'Ethscription retrieved successfully' do
        schema type: :object,
               properties: {
                result: { '$ref' => '#/components/schemas/EthscriptionWithTransfers' }
               },
               description: "The ethscription's details"

        run_test!
      end
      
      response '404', 'Ethscription not found' do
        schema type: :object,
               properties: {
                 error: { type: :string, example: 'Record not found' }
               },
               description: 'Error message indicating the ethscription was not found'

        run_test!
      end
    end
  end
  
  path '/ethscriptions/{tx_hash_or_ethscription_number}/data' do
    get 'Show Ethscription Data' do
      tags 'Ethscriptions'
      operationId 'getEthscriptionData'
      produces 'application/octet-stream', 'image/png', 'text/plain'
      description 'Retrieves the raw content data of an ethscription and serves it according to its content type.'
      
      parameter name: :tx_hash_or_ethscription_number,
                in: :path,
                type: :string,
                description: 'The ethscription number or transaction hash to retrieve data for.',
                required: true,
                example: "0"

      response '200', 'Data retrieved successfully' do
        header 'Content-Type', description: 'The MIME type of the data.', schema: { type: :string }

        schema type: :string,
               format: :binary,
               description: 'Returns the raw data of an ethscription as indicated by the content type of the stored data URI. The content type in the response depends on the ethscription’s data.',
               example: '\u0000\u0001\u0002\u0003\u0004\u0005\u0006\a\b\t\n\v\f\r\u000E\u000F'

        run_test!
      end

      response '404', 'Ethscription not found' do
        schema type: :object,
               properties: {
                 error: { type: :string, example: 'Record not found' }
               },
               description: 'Error message indicating the ethscription was not found'

        run_test!
      end
    end
  end
  
  path '/ethscriptions/{tx_hash_or_ethscription_number}/attachment' do
    get 'Show Ethscription Attachment Data' do
      tags 'Ethscriptions'
      operationId 'getEthscriptionAttachment'
      produces 'application/octet-stream', 'image/png', 'text/plain'
      description <<~DESC
        Retrieves the raw attachment of an ethscription and serves it according to its content type. Only available when an attachment is present. Attachments are created via blobs per esip-8.
      DESC
  
      parameter name: :tx_hash_or_ethscription_number, in: :path, type: :string, required: true,
                description: 'The ethscription number or transaction hash to retrieve the attachment for.',
                example: '0xcf23d640184114e9d870a95f0fdc3aa65e436c5457d5b6ee2e3c6e104420abd1'
  
      response '200', 'Attachment retrieved successfully' do
        header 'Content-Type', description: 'The MIME type of the attachment.', schema: { type: :string }

        schema type: :string,
               format: :binary,
               description: 'Returns the raw attachment data of an ethscription. The content type in the response depends on the ethscription’s attachment content type.',
               example: '\u0000\u0001\u0002\u0003\u0004\u0005\u0006\a\b\t\n\v\f\r\u000E\u000F'

        run_test!
      end
  
      response '404', 'Attachment not found' do
        schema type: :object,
               properties: {
                 error: { type: :string, example: 'Attachment not found' }
               },
               description: 'Indicates that no attachment was found for the provided ID or transaction hash.'
               
        run_test!
      end
    end
  end
  
  path '/ethscriptions/exists/{sha}' do
    get 'Check if Ethscription Exists' do
      tags 'Ethscriptions'
      operationId 'checkEthscriptionExists'
      produces 'application/json'
      description <<~DESC
        Checks if an Ethscription exists by its content SHA hash. Returns a boolean indicating existence and, if present, the ethscription itself.
      DESC
  
      parameter name: :sha, in: :path, type: :string, required: true,
                description: 'The SHA hash of the ethscription content to check for existence.',
                example: '0x2817fd9cf901e4435253881550731a5edc5e519c19de46b08e2b19a18e95143e'
  
      response '200', 'Check performed successfully' do
        schema type: :object,
               properties: {
                 result: {
                   type: :object,
                   properties: {
                     exists: { type: :boolean, example: true },
                     ethscription: { '$ref' => '#/components/schemas/Ethscription' }
                   }
                 }
               },
               description: 'A boolean indicating whether the Ethscription exists, and the Ethscription itself if it does.'
  
        run_test!
      end
  
      response '404', 'SHA hash parameter missing' do
        schema type: :object,
               properties: {
                 error: { type: :string, example: 'SHA hash parameter missing or invalid' }
               },
               description: 'Error message indicating the required SHA hash parameter is missing or invalid.'
      end
    end
  end
  
  path '/ethscriptions/exists_multi' do
    post 'Check Multiple Ethscriptions Existence' do
      tags 'Ethscriptions'
      operationId 'checkMultipleEthscriptionsExistence'
      consumes 'application/json'
      produces 'application/json'
      description <<~DESC
        Accepts a list of SHA hashes and checks for the existence of Ethscriptions corresponding to each SHA. Returns a mapping from SHA hashes to their corresponding Ethscription transaction hashes, if found; otherwise maps to `null`. Max input: 100 shas.
      DESC
  
      parameter name: :shas, in: :body, schema: {
        type: :object,
        properties: {
          shas: { 
            type: :array, 
            items: { type: :string },
            description: 'An array of SHA hashes to check for Ethscription existence.',
            example: ['0x2817fd9cf901e4435253881550731a5edc5e519c19de46b08e2b19a18e95143e', '0xdcb130d85be00f8fd735ddafcba1cc83f99ba8dab0fc79c833401827b615c92b']
          }
        },
        required: ['shas']
      }
      
      response '200', 'Existence check performed successfully' do
        schema type: :object,
               properties: {
                 result: {
                   type: :object,
                   additionalProperties: {
                     type: :string,
                     nullable: true,
                     description: 'Transaction hash associated with the SHA. Null if the SHA does not correspond to an existing Ethscription.'
                   },
                   description: 'Mapping from SHA hashes to Ethscription transaction hashes or null if the Ethscription does not exist.'
                 }
               },
               description: 'Successfully returns a mapping from provided SHA hashes to their corresponding Ethscription transaction hashes or null if not found.',
               example: { result: {
                 "0x2817fd9cf901e4435253881550731a5edc5e519c19de46b08e2b19a18e95143e" => "0xcf23d640184114e9d870a95f0fdc3aa65e436c5457d5b6ee2e3c6e104420abd1",
                 "0xdcb130d85be00f8fd735ddafcba1cc83f99ba8dab0fc79c833401827b615c92b" => nil
               }}
  
        run_test!
      end
      
      response '400', 'Too many SHAs' do
        schema type: :object,
               properties: {
                 error: { type: :string, example: 'Too many SHAs' }
               },
               description: 'Error response indicating that the request contained too many SHA hashes (limit is 100).'
      end
    end
  end
  
  path '/ethscriptions/data_multi' do
    post 'Get Multiple Ethscription Data' do
      tags 'Ethscriptions'
      operationId 'getMultipleEthscriptionData'
      consumes 'application/json'
      produces 'application/json'
      description <<~DESC
        Accepts a list of ethscription IDs (transaction hashes or ethscription numbers) and returns the data for each. Returns a mapping from IDs to their corresponding data objects, if found; otherwise maps to `null`. Max input: 100 IDs.
      DESC

      parameter name: :ids, in: :body, schema: {
        type: :object,
        properties: {
          ids: { 
            type: :array, 
            items: { type: :string },
            description: 'An array of ethscription IDs (transaction hashes or ethscription numbers) to retrieve data for.',
            example: ['0', '0x0ef100873db4e3b7446e9a3be0432ab8bc92119d009aa200f70c210ac9dcd4a6']
          }
        },
        required: ['ids']
      }
      
      response '200', 'Data retrieved successfully' do
        schema type: :object,
               properties: {
                 result: {
                   type: :object,
                   additionalProperties: {
                     type: :object,
                     nullable: true,
                     properties: {
                       data: { type: :string, description: 'Base64 encoded data' },
                       mimetype: { type: :string, description: 'MIME type of the data' },
                       ethscription_number: { type: :string, description: 'Ethscription number' },
                       transaction_hash: { type: :string, description: 'Transaction hash' }
                     },
                     description: 'Data object for the ethscription. Null if the ethscription does not exist.'
                   },
                   description: 'Mapping from ethscription IDs to their corresponding data objects or null if not found.'
                 }
               },
               description: 'Successfully returns a mapping from provided IDs to their corresponding data objects or null if not found.'

        run_test!
      end
      
      response '400', 'Bad request' do
        schema type: :object,
               properties: {
                 error: { type: :string, example: 'No IDs provided' }
               },
               description: 'Error response indicating bad request (no IDs provided or too many IDs).'
      end
    end
  end
  
  path '/ethscriptions/newer' do
    get 'List Newer Ethscriptions' do
      tags 'Ethscriptions'
      operationId 'getNewerEthscriptions'
      consumes 'application/json'
      produces 'application/json'
      description <<~DESC
        Retrieves Ethscriptions that are newer than a specified block number, optionally filtered by mimetype, initial owner, and other criteria. Returns Ethscriptions grouped by block, including block metadata and a count of total future Ethscriptions. The Facet VM relies on this endpoint to retrieve new Ethscriptions.
      DESC
  
      parameter name: :mimetypes, in: :query, type: :array, items: { type: :string },
                description: 'Optional list of mimetypes to filter Ethscriptions by.', required: false
  
      parameter name: :initial_owner, in: :query, type: :string,
                description: 'Optional initial owner to filter Ethscriptions by.', required: false
  
      parameter name: :block_number, in: :query, type: :integer,
                description: 'Block number to start retrieving newer Ethscriptions from.', required: true
  
      parameter name: :past_ethscriptions_count, in: :query, type: :integer,
                description: 'Optional count of past Ethscriptions for checksum validation.', required: false
  
      parameter name: :past_ethscriptions_checksum, in: :query, type: :string,
                description: 'Optional checksum of past Ethscriptions for validation.', required: false
  
      parameter name: :max_ethscriptions, in: :query, type: :integer,
                description: 'Maximum number of Ethscriptions to return.', required: false, example: 50
  
      parameter name: :max_blocks, in: :query, type: :integer,
                description: 'Maximum number of blocks to include in the response.', required: false, example: 500
  
      response '200', 'Newer Ethscriptions retrieved successfully' do
        schema type: :object,
               properties: {
                 total_future_ethscriptions: { type: :integer, example: 100 },
                 blocks: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       blockhash: { type: :string, example: '0x0204cb...' },
                       parent_blockhash: { type: :string, example: '0x0204cb...' },
                       block_number: { type: :integer, example: 123456789 },
                       timestamp: { type: :integer, example: 1678900000 },
                       ethscriptions: {
                         type: :array,
                         items: { '$ref' => '#/components/schemas/Ethscription' }
                       }
                     }
                   },
                   description: 'List of blocks with their Ethscriptions.'
                 }
               },
               description: 'A list of newer Ethscriptions grouped by block, including metadata about each block and a count of total future Ethscriptions.'
  
        run_test!
      end
  
      response '422', 'Unprocessable entity' do
        schema type: :object,
               properties: {
                 error: { 
                   type: :object,
                   properties: {
                     message: { type: :string },
                     resolution: { type: :string }
                   }
                 }
               },
               description: 'Error response for various failure scenarios, such as block not yet imported or checksum mismatch.'
  
        run_test!
      end
    end
  end
end

