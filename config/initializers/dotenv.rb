unless Rails.env.production?
  require 'dotenv'
  
  Dotenv.load

  if ENV['L1_NETWORK'] == 'sepolia'
    sepolia_env = Rails.root.join('.env.sepolia')
    Dotenv.load(sepolia_env) if File.exist?(sepolia_env)
  elsif ENV['L1_NETWORK'] == 'mainnet'
    mainnet_env = Rails.root.join('.env.mainnet')
    Dotenv.load(mainnet_env) if File.exist?(mainnet_env)
  else
    raise "Unknown L1_NETWORK: #{ENV['L1_NETWORK']}"
  end
end
