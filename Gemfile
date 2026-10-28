# frozen_string_literal: true

source 'https://rubygems.org'

# Specify your gem's dependencies in field_struct.gemspec
gemspec

gem 'rake', '~> 13.0'

gem 'rspec', '~> 3.0'

gem 'rubocop', '~> 1.21'

gem 'simplecov', '~> 0.22', require: false

# Type signatures: sord generates sig/field_struct.rbs from YARD comments;
# rbs validates the generated sigs.
gem 'rbs', '~> 3.0', require: false
gem 'sord', '~> 7.0', require: false

# Documentation: yard renders HTML docs to doc/ from YARD comments.
# Pulled in transitively by sord, but we depend on it directly through
# the docs:* and release:check rake tasks.
gem 'yard', '~> 0.9', require: false
