class ApplicationController < ActionController::API
  include FacetRailsCommon::ApplicationControllerMethods
  
  # Ensure all API endpoints support CORS when Origin header is present
  before_action :set_cors_headers
  
  private
  
  def set_cors_headers
    if request.headers['Origin']
      response.headers['Access-Control-Allow-Origin'] = '*'
      response.headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, PATCH, DELETE, OPTIONS, HEAD'
      response.headers['Access-Control-Allow-Headers'] = 'Origin, Content-Type, Accept, Authorization, X-Requested-With'
      response.headers['Cross-Origin-Resource-Policy'] = 'cross-origin'
    end
  end
end
