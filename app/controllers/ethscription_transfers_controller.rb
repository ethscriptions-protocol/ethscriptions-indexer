class EthscriptionTransfersController < ApplicationController
  cache_actions_on_block
  
  def index
    scope = filter_by_params(EthscriptionTransfer.all,
      :from_address,
      :to_address,
      :transaction_hash,
      :block_number,
      :block_timestamp,
      :block_blockhash,
      :ethscription_transaction_hash,
      :enforced_previous_owner
    )
    
    to_or_from = parse_param_array(params[:to_or_from])
    
    if to_or_from.present?
      scope = scope.where(from_address: to_or_from)
                   .or(scope.where(to_address: to_or_from))
    end
    
    ethscription_token_tick = parse_param_array(params[:ethscription_token_tick]).first
    ethscription_token_protocol = parse_param_array(params[:ethscription_token_protocol]).first
    
    if ethscription_token_tick && ethscription_token_protocol
      tokens = Ethscription.with_token_tick_and_protocol(
        ethscription_token_tick,
        ethscription_token_protocol
      ).select(:transaction_hash)
      
      scope = scope.where(ethscription_transaction_hash: tokens)
    end
    
    results, pagination_response = paginate(scope)
    
    render json: {
      result: numbers_to_strings(results),
      pagination: pagination_response
    }
  end
end
