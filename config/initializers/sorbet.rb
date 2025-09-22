# Set up Sorbet runtime
require 'sorbet-runtime'

# Make T::Sig available globally
class Module
  include T::Sig
end