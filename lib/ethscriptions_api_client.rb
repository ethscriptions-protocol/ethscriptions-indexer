class EthscriptionsApiClient
  BASE_URL = ENV['ETHSCRIPTIONS_API_BASE_URL'].to_s

  class << self
    def fetch_block_data(block_number)
      creations = fetch_creations(block_number)
      transfers = fetch_transfers(block_number)

      {
        creations: normalize_creations(creations),
        transfers: normalize_transfers(transfers)
      }
    rescue => e
      Rails.logger.error "Failed to fetch block data for #{block_number}: #{e.message}"
      raise
    end

    # private

    def fetch_creations(block_number)
      fetch_paginated("/ethscriptions", {
        block_number: block_number,
        max_results: 50 # Respect swagger max and paginate for full coverage
      })
    end

    def fetch_transfers(block_number)
      fetch_paginated("/ethscription_transfers", {
        block_number: block_number,
        max_results: 50 # Respect swagger max and paginate for full coverage
      })
    end

    def fetch_paginated(path, params)
      results = []
      page_key = nil

      loop do
        query_params = params.dup
        query_params[:page_key] = page_key if page_key

        data = fetch_json(path, query_params)

        # API returns { result: [...], pagination: { has_more:, page_key: } }
        page = data['result'] || []
        pagination = data['pagination'] || {}

        results.concat(page)

        has_more = pagination['has_more']
        page_key = pagination['page_key']
        break unless has_more
      end

      results
    end

    def fetch_json(path, params = {})
      uri = URI("#{BASE_URL}#{path}")
      uri.query = URI.encode_www_form(params) if params.any?

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.open_timeout = 5
      http.read_timeout = 10

      request = Net::HTTP::Get.new(uri)
      request['Accept'] = 'application/json'

      response = http.request(request)

      unless response.code == '200'
        raise "API request failed: #{response.code} - #{response.body}"
      end

      JSON.parse(response.body)
    end

    def normalize_creations(data)
      data.map do |item|
        tx_hash = (item['transaction_hash'] || '').downcase
        creator = (item['creator'] || '').downcase
        initial_owner = (item['initial_owner'] || item['creator'] || '').downcase
        current_owner = (item['current_owner'] || '').downcase
        previous_owner = (item['previous_owner'] || '').downcase

        # Decode the b64_content field if present
        content = Base64.decode64(item['b64_content'])

        {
          tx_hash: tx_hash,
          transaction_hash: tx_hash, # Include both for compatibility
          block_number: item['block_number'],
          transaction_index: item['transaction_index'],
          block_timestamp: item['block_timestamp'],
          block_blockhash: item['block_blockhash'],
          event_log_index: item['event_log_index'],
          ethscription_number: item['ethscription_number'],
          creator: creator,
          initial_owner: initial_owner,
          current_owner: current_owner,
          previous_owner: previous_owner,
          content_uri: item['content_uri'],
          content_sha: "0x" + Digest::SHA256.hexdigest(content),
          esip6: item['esip6'] || false,
          mimetype: item['mimetype'],
          media_type: item['media_type'],
          mime_subtype: item['mime_subtype'],
          gas_price: item['gas_price'],
          gas_used: item['gas_used'],
          transaction_fee: item['transaction_fee'],
          value: item['value'],
          attachment_sha: item['attachment_sha'],
          attachment_content_type: item['attachment_content_type'],
          b64_content: item['b64_content'],  # Keep the original base64
          content: content  # Add decoded content
        }
      end
    end

    def normalize_transfers(data)
      data.map do |item|
        tx_index = item['transaction_index']
        tx_index = tx_index.to_i if tx_index
        log_index = item['event_log_index']
        log_index = log_index.to_i if log_index

        {
          token_id: (item['ethscription_transaction_hash'] || '').downcase,  # The ethscription being transferred
          tx_hash: (item['transaction_hash'] || '').downcase,                # The transfer transaction
          from: (item['from_address'] || '').downcase,
          to: (item['to_address'] || '').downcase,
          block_number: item['block_number'],
          transaction_index: tx_index,
          event_log_index: log_index
        }
      end
    end
  end
end
