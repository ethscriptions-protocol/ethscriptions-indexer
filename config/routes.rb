Rails.application.routes.draw do
  def draw_routes
    resources :ethscriptions, only: [:index, :show] do
      collection do
        get "/:id/data", to: "ethscriptions#data"
        # get "/newer_ethscriptions", to: "ethscriptions#newer_ethscriptions"
        # get "/newer", to: "ethscriptions#newer_ethscriptions"
        get '/owned_by/:owned_by_address', to: 'ethscriptions#index'
        get "/exists/:sha", to: "ethscriptions#exists"
        post "/exists_multi", to: "ethscriptions#exists_multi"
      end
      
      member do
        get 'attachment', to: 'ethscriptions#attachment'
      end
    end
    
    resources :ethscription_transfers, only: [:index] do
    end
    
    resources :blocks, only: [:index, :show] do
      collection do
        get "/newer_blocks", to: "blocks#newer_blocks"
      end
    end
    
    resources :tokens, only: [:index] do
      collection do
        get "/:protocol/:tick", to: "tokens#show"
        get "/:protocol/:tick/historical_state", to: "tokens#historical_state"
        
        get "/balance_of", to: "tokens#balance_of"
        
        get "/validate_token_items", to: "tokens#validate_token_items"
        post "/validate_token_items", to: "tokens#validate_token_items"
      end
    end
    
    get "/status", to: "status#indexer_status"
  end

  draw_routes

  # Support legacy indexer namespace
  scope :api do
    draw_routes
  end
  
  scope :v2 do
    draw_routes
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
end
