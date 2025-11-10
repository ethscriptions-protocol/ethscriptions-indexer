class EthscriptionsApiClient
  BASE_URL = ENV['ETHSCRIPTIONS_API_BASE_URL'].to_s

  # Single error type for all API issues (after exhausting retries)
  class ApiUnavailableError < StandardError; end

  # Internal error types used for retry logic
  class HttpError < StandardError
    attr_reader :code, :http_message

    def initialize(code, http_message)
      @code = code
      @http_message = http_message
      super("HTTP error: #{code} #{http_message}")
    end
  end
  class ApiError < StandardError; end
  class NetworkError < StandardError; end

  class << self
    def fetch_block_data(block_number)
      creations = fetch_creations(block_number)
      transfers = fetch_transfers(block_number)

      {
        creations: normalize_creations(creations),
        transfers: normalize_transfers(transfers)
      }
    rescue HttpError, ApiError, NetworkError => e
      # Wrap all internal errors into a single type for callers
      Rails.logger.error "API unavailable for block #{block_number} after retries: #{e.message}"
      raise ApiUnavailableError, "API unavailable after #{ENV.fetch('ETHSCRIPTIONS_API_RETRIES', 7)} retries: #{e.message}"
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

    def fetch_single_ethscription(number)
      # Fetch a single ethscription by its number
      path = "/ethscriptions/#{number}"

      begin
        data = fetch_json(path)
        # The show endpoint returns the ethscription directly
        normalize_creations([data['result']]).first
      rescue HttpError => e
        if e.code == 404
          # Ethscription doesn't exist
          nil
        else
          # Re-raise other HTTP errors for retry handling
          raise
        end
      end
    rescue HttpError, ApiError, NetworkError => e
      # Wrap all internal errors into a single type for callers
      Rails.logger.error "API unavailable for ethscription ##{number} after retries: #{e.message}"
      raise ApiUnavailableError, "API unavailable after #{ENV.fetch('ETHSCRIPTIONS_API_RETRIES', 7)} retries: #{e.message}"
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
      # Add API key to query params if provided
      api_key = ENV['ETHSCRIPTIONS_API_KEY']
      params = params.merge(api_key: api_key) if api_key.present?

      uri = URI("#{BASE_URL}#{path}")
      uri.query = URI.encode_www_form(params) if params.any?

      # Use Retriable for automatic retries on transient errors
      Retriable.retriable(
        tries: ENV.fetch('ETHSCRIPTIONS_API_RETRIES', 7).to_i,
        base_interval: 1,
        max_interval: 32,
        multiplier: 2,
        rand_factor: 0.4,
        on: [Net::ReadTimeout, Net::OpenTimeout, HttpError, NetworkError, ApiError],
        on_retry: ->(exception, try, elapsed_time, next_interval) {
          Rails.logger.info "Retrying Ethscriptions API #{path} (attempt #{try}, next delay: #{next_interval.round(2)}s) - #{exception.message}"
        }
      ) do
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'

        request = Net::HTTP::Get.new(uri)
        request['Accept'] = 'application/json'

        begin
          response = http.request(request)
        rescue SocketError, Errno::ECONNREFUSED, Errno::ECONNRESET => e
          # Network-level errors - will be retried
          raise NetworkError, "Network error: #{e.message}"
        rescue Net::OpenTimeout, Net::ReadTimeout => e
          # Timeout errors - will be retried
          raise NetworkError, "Timeout: #{e.message}"
        end

        unless response.code == '200'
          # HTTP errors - will be retried if in retry list
          raise HttpError.new(response.code.to_i, response.body)
        end

        begin
          JSON.parse(response.body)
        rescue JSON::ParserError => e
          # JSON parsing errors (often Cloudflare error pages) - will be retried
          raise ApiError, "Invalid JSON response: #{e.message}"
        end
      end
    end

    def normalize_creations(data)
      data.map do |item|
        tx_hash = (item['transaction_hash'] || '').downcase
        creator = (item['creator'] || '').downcase
        initial_owner = (item['initial_owner'] || item['creator'] || '').downcase
        current_owner = (item['current_owner'] || '').downcase
        previous_owner = (item['previous_owner'] || '').downcase

        content = Base64.decode64(item['b64_content'])

        {
          tx_hash: tx_hash,
          transaction_hash: tx_hash, # Include both for compatibility
          block_number: item['block_number'],
          l1_block_number: item['block_number'],
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
          content_hash: "0x" +  Eth::Util.keccak256(content).unpack1('H*'),
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
