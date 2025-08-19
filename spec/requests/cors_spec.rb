require 'rails_helper'

RSpec.describe 'CORS for Data Endpoint', type: :request do
  describe 'Ethscriptions data endpoint CORS handling' do
    context 'OPTIONS preflight request' do
      it 'responds with appropriate CORS headers for preflight request' do
        options "/ethscriptions/1/data", 
                headers: { 
                  'Origin' => 'https://example.com',
                  'Access-Control-Request-Method' => 'GET',
                  'Access-Control-Request-Headers' => 'content-type'
                }
        
        expect(response.status).to eq(200)
        expect(response.headers['Access-Control-Allow-Origin']).to eq('*')
        expect(response.headers['Access-Control-Allow-Methods']).to eq('GET, OPTIONS')
        expect(response.headers['Access-Control-Allow-Headers']).to eq('Origin, Content-Type, Accept, Authorization')
        expect(response.headers['Access-Control-Max-Age']).to eq('3600')
      end
    end
    
    context 'GET request with Origin header' do
      it 'includes CORS headers when Origin header is present' do
        # Note: This test may fail if ethscription #1 doesn't exist, but the CORS headers should still be set
        get "/ethscriptions/1/data", 
            headers: { 'Origin' => 'https://example.com' }
        
        # Check CORS headers are present regardless of whether the ethscription exists
        expect(response.headers['Access-Control-Allow-Origin']).to eq('*')
        expect(response.headers['Access-Control-Allow-Methods']).to eq('GET, OPTIONS')
        expect(response.headers['Access-Control-Allow-Headers']).to eq('Origin, Content-Type, Accept, Authorization')
      end
      
      it 'does not include CORS headers when Origin header is not present' do
        get "/ethscriptions/1/data"
        
        # CORS headers should not be set when no Origin header is present
        expect(response.headers['Access-Control-Allow-Origin']).to be_nil
      end
    end
  end
end