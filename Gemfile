# frozen_string_literal: true

source 'https://rubygems.org'

# Specify your gem's dependencies in omniauth-cas.gemspec
gemspec

if RUBY_VERSION < '2.2.2'
  # Rack 2 needs Ruby 2.2.2+
  gem 'rack', '< 2'
end

if RUBY_VERSION >= '2.7'
  gem 'rubocop', require: false
  gem 'rubocop-performance', require: false
  gem 'rubocop-rake', require: false
  gem 'rubocop-rspec', require: false
end

gem 'awesome_print'
gem 'byebug'
gem 'rack-test'
gem 'rake'
gem 'rspec'
gem 'webmock'
