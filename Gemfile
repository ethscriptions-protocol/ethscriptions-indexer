source "https://rubygems.org"

ruby "3.4.4"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 7.1.2"

# Use postgresql as the database for Active Record

# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"

# Build JSON APIs with ease [https://github.com/rails/jbuilder]
# gem "jbuilder"

# Use Kredis to get higher-level data types in Redis [https://github.com/rails/kredis]
# gem "kredis"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ mswin mswin64 mingw x64_mingw jruby ]

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Use Rack CORS for handling Cross-Origin Resource Sharing (CORS), making cross-origin Ajax possible
# gem "rack-cors"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri mswin mswin64 mingw x64_mingw ]
  gem "pry"
  gem "rspec-rails"
  gem 'rswag-specs'
end

group :development do
  # Speed up commands on slow machines / big apps [https://github.com/rails/spring]
  # gem "spring"
  gem "stackprof", "~> 0.2.25"
end

gem "dotenv-rails", "~> 2.8", groups: [:development, :test]

# For Ethscription content compression
gem "fastlz", "~> 0.1.0"

gem "dalli", "~> 3.2"

gem "kaminari", "~> 1.2"

gem "rack-cors", "~> 2.0"

gem "eth", github: "0xFacet/eth.rb", branch: "sync/v0.5.16-nohex"

gem 'sorbet', :group => :development
gem 'sorbet-runtime'
gem 'tapioca', require: false, :group => [:development, :test]

gem "scout_apm", "~> 5.3"

gem "memoist", "~> 0.16.2"

gem "awesome_print", "~> 1.9"


gem "redis", "~> 5.0"

gem 'facet_rails_common', git: 'https://github.com/0xfacet/facet_rails_common.git'

gem "cbor", "~> 0.5.9"

gem 'rswag-api'

gem 'rswag-ui'

gem 'keccak', '~> 1.3'
gem "memery", "~> 1.5"

gem "httparty", "~> 0.22.0"

gem "jwt", "~> 2.8"

gem "clockwork", "~> 3.0"

gem "airbrake", "~> 13.0"
gem "clipboard", "~> 2.0", :group => [:development, :test]

gem "parallel", "~> 1.25"

gem "net-http-persistent", "~> 4.0"

gem 'benchmark'
gem 'ostruct'

gem "oj", "~> 3.16"

gem "retriable", "~> 3.1"
