source ENV['GEM_SOURCE'] || 'https://rubygems.org'

group :test do
  gem 'voxpupuli-test', '~> 15.0', require: false
  gem 'puppet_metadata', '~> 6.1', require: false
  gem 'openvox', ENV.fetch('OPENVOX_GEM_VERSION', ['>= 7', '< 9']), require: false
end

gem 'rake', require: false
