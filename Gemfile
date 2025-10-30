source "https://rubygems.org"

ruby "3.4.4"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "8.0.2.1"

# Use postgresql as the database for Active Record

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

gem "eth", github: "0xFacet/eth.rb", branch: "sync/v0.5.16-nohex"

gem 'sorbet', :group => :development
gem 'sorbet-runtime'
gem 'tapioca', require: false, :group => [:development, :test]

gem "awesome_print", "~> 1.9"

gem 'facet_rails_common', git: 'https://github.com/0xfacet/facet_rails_common.git', branch: 'lenient_base64'

gem "memery", "~> 1.5"

gem "httparty", "~> 0.22.0"

gem "jwt", "~> 2.8"

gem "clockwork", "~> 3.0"

gem "airbrake", "~> 13.0"
gem "clipboard", "~> 2.0", :group => [:development, :test]

gem "net-http-persistent", "~> 4.0"

gem 'benchmark'
gem 'ostruct'

gem "retriable", "~> 3.1"

# Database and job processing
gem "sqlite3", ">= 2.1"
gem "solid_queue"
