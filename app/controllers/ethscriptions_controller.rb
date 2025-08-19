class EthscriptionsController < ApplicationController
  cache_actions_on_block only: [:index, :show, :newer_ethscriptions]
  
  def index
    if params[:owned_by_address].present?
      params[:current_owner] = params[:owned_by_address]
    end
    
    scope = filter_by_params(Ethscription.all,
      :current_owner,
      :creator,
      :initial_owner,
      :previous_owner,
      :mimetype,
      :media_type,
      :mime_subtype,
      :content_sha,
      :transaction_hash,
      :block_number,
      :block_timestamp,
      :block_blockhash,
      :ethscription_number,
      :attachment_sha,
      :attachment_content_type
    )
    
    if params[:after_block].present?
      scope = scope.where('block_number > ?', params[:after_block].to_i)
    end
    
    if params[:before_block].present?
      scope = scope.where('block_number < ?', params[:before_block].to_i)
    end
    
    scope = scope.where.not(attachment_sha: nil) if params[:attachment_present] == "true"
    scope = scope.where(attachment_sha: nil) if params[:attachment_present] == "false"

    include_latest_transfer = params[:include_latest_transfer].present?
    
    if include_latest_transfer
      scope = scope.includes(:ethscription_transfers)
    end
    
    token_tick = parse_param_array(params[:token_tick]).first
    token_protocol = parse_param_array(params[:token_protocol]).first
    transferred_in_tx = parse_param_array(params[:transferred_in_tx])
    
    if token_tick && token_protocol
      scope = scope.with_token_tick_and_protocol(token_tick, token_protocol)
    end
    
    if transferred_in_tx.present?
      sub_query = EthscriptionTransfer.where(transaction_hash: transferred_in_tx).select(:ethscription_transaction_hash)
      scope = scope.where(transaction_hash: sub_query)
    end
    
    transaction_hash_only = params[:transaction_hash_only].present? && !include_latest_transfer
    
    if transaction_hash_only
      scope = scope.select(:id, :transaction_hash)
    end
    
    results_limit = if transaction_hash_only
      1000
    elsif include_latest_transfer
      50
    else
      100
    end
    
    results, pagination_response = paginate(
      scope,
      results_limit: results_limit
    )
    
    results = results.map do |ethscription|
      ethscription.as_json(include_latest_transfer: include_latest_transfer)
    end
    
    render json: {
      result: numbers_to_strings(results),
      pagination: pagination_response
    }
  end
  
  def show
    scope = Ethscription.all.includes(:ethscription_transfers)
    
    id_or_hash = params[:id].to_s.downcase
    
    scope = id_or_hash.match?(/\A0x[0-9a-f]{64}\z/) ? 
      scope.where(transaction_hash: id_or_hash) : 
      scope.where(ethscription_number: id_or_hash)
    
    ethscription = Rails.cache.fetch(["ethscription-api-show", scope]) do
      scope.first
    end
    
    if !ethscription
      render json: { error: "Not found" }, status: 404
      return
    end
    
    json = numbers_to_strings(ethscription.as_json(include_transfers: true))
    
    render json: {
      result: json
    }
  end
  
  def data
    scope = Ethscription.all
    
    id_or_hash = params[:id].to_s.downcase
    
    scope = id_or_hash.match?(/\A0x[0-9a-f]{64}\z/) ? 
      scope.where(transaction_hash: id_or_hash) : 
      scope.where(ethscription_number: id_or_hash)
    
    blockhash, block_number = scope.pick(:block_blockhash, :block_number)
    
    unless blockhash.present?
      head 404
      return
    end
    
    response.headers.delete('X-Frame-Options')
    
    set_cache_control_headers(
      max_age: 6,
      s_max_age: 1.minute,
      etag: blockhash,
      extend_cache_if_block_final: block_number
    ) do
      item = scope.first
      
      uri_obj = item.parsed_data_uri
      
      send_data(uri_obj.decoded_data, type: uri_obj.mimetype, disposition: 'inline')
    end
  end
  
  def attachment
    scope = Ethscription.all
    
    id_or_hash = params[:id].to_s.downcase
    
    scope = id_or_hash.match?(/\A0x[0-9a-f]{64}\z/) ? 
      scope.where(transaction_hash: id_or_hash) : 
      scope.where(ethscription_number: id_or_hash)
    
    sha, blockhash, block_number = scope.pick(:attachment_sha, :block_blockhash, :block_number)
    
    attachment_scope = EthscriptionAttachment.where(sha: sha)
    
    unless attachment_scope.exists?
      head 404
      return
    end
    
    response.headers.delete('X-Frame-Options')
    
    set_cache_control_headers(
      max_age: 6,
      s_max_age: 1.minute,
      etag: [sha, blockhash],
      extend_cache_if_block_final: block_number
    ) do
      attachment = attachment_scope.first
      
      send_data(attachment.content, type: attachment.content_type_with_encoding, disposition: 'inline')    
    end
  end
  
  def exists
    existing = Ethscription.find_by_content_sha(params[:sha])
  
    render json: {
      result: {
        exists: existing.present?,
        ethscription: existing
      }
    }
  end
  
  def exists_multi
    shas = Array.wrap(params[:shas]).sort.uniq
    
    if shas.size > 100
      render json: { error: "Too many SHAs" }, status: 400
      return
    end
    
    result = Rails.cache.fetch(["ethscription-api-exists-multi", shas], expires_in: 12.seconds) do
      existing_ethscriptions = Ethscription.where(content_sha: shas).pluck(:content_sha, :transaction_hash)
    
      sha_to_transaction_hash = existing_ethscriptions.to_h
    
      shas.each do |sha|
        sha_to_transaction_hash[sha] ||= nil
      end
      
      sha_to_transaction_hash
    end
  
    render json: { result: result }
  end
  
  def newer_ethscriptions
    mimetypes = params[:mimetypes] || []
    initial_owner = params[:initial_owner]
    requested_block_number = params[:block_number].to_i
    client_past_ethscriptions_count = params[:past_ethscriptions_count]
    past_ethscriptions_checksum = params[:past_ethscriptions_checksum]
    
    system_max_ethscriptions = ENV.fetch('MAX_ETHSCRIPTIONS_PER_VM_REQUEST', 25).to_i
    system_max_blocks = ENV.fetch('MAX_BLOCKS_PER_VM_REQUEST', 50).to_i
    
    max_ethscriptions = [params[:max_ethscriptions]&.to_i || 50, system_max_ethscriptions].min
    max_blocks = [params[:max_blocks]&.to_i || 500, system_max_blocks].min

    scope = Ethscription.all.oldest_first
    scope = scope.where(mimetype: mimetypes) if mimetypes.present?
    scope = scope.where(initial_owner: initial_owner) if initial_owner.present?
    
    unless scope.exists?
      render json: {
        error: {
          message: "No matching ethscriptions found",
          resolution: :retry_with_delay
        }
      }, status: :unprocessable_entity
      return
    end
    
    requested_block_number = [requested_block_number, scope.limit(1).pluck(:block_number).first].max
    
    we_are_up_to_date = EthBlock.where(block_number: requested_block_number).
      where.not(imported_at: nil).exists?
    
    unless we_are_up_to_date
      render json: {
        error: {
          message: "Block not yet imported. Please try again later",
          resolution: :retry
        }
      }, status: :unprocessable_entity
      return
    end
    
    last_ethscription_block = scope.where('block_number >= ? AND block_number < ?', 
                                requested_block_number, 
                                requested_block_number + max_blocks)
                          .order(:block_number, :transaction_index)
                          .offset(max_ethscriptions - 1)
                          .pluck(:block_number)
                          .first

    last_block_in_range = last_ethscription_block || requested_block_number + max_blocks - 1
    
    last_block_in_range -= 1 if last_block_in_range > requested_block_number
    
    block_range = (requested_block_number..last_block_in_range).to_a
    
    all_blocks_in_range = EthBlock.where(block_number: block_range).where.not(imported_at: nil).order(:block_number).index_by(&:block_number)
    
    if all_blocks_in_range[requested_block_number].nil?
      render json: {
        error: {
          message: "Block not yet imported. Please try again later",
          resolution: :retry
        }
      }, status: :unprocessable_entity
      return
    end
    
    ethscriptions_in_range = scope.where(block_number: block_range)

    ethscriptions_by_block = ethscriptions_in_range.group_by(&:block_number)
  
    block_data = all_blocks_in_range.map do |block_number, block|
      current_block_ethscriptions = ethscriptions_by_block[block_number] || []
      {
        blockhash: block.blockhash,
        parent_blockhash: block.parent_blockhash,
        block_number: block.block_number,
        timestamp: block.timestamp.to_i,
        ethscriptions: current_block_ethscriptions
      }
    end
    
    total_ethscriptions_in_future_blocks = scope.where('block_number > ?', block_range.last).count
    
    render json: {
      total_future_ethscriptions: total_ethscriptions_in_future_blocks,
      blocks: block_data
    }
  end
end
