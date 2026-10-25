# frozen_string_literal: true

# The gems the site's runnable code blocks are checked against.
# Pin to the RELEASED tags the docs describe; bump these when a new release ships.
source 'https://rubygems.org'

gem 'field_struct', git: 'https://github.com/Paymentbox-com/field_struct', tag: 'v0.16.0'
gem 'actionable-rb', git: 'https://github.com/Paymentbox-com/actionable', tag: 'v1.10.0'

# Extra gems some how-to guides need so their examples run too (they are only
# required by the pages that use them): the Rails adapter's transactions and
# after_commit (activerecord + in-memory sqlite3), the background-job adapter
# under ActiveJob, and the RSpec matchers and stubs.
gem 'activejob', '~> 8.0'
gem 'activerecord', '~> 8.0'
gem 'rspec', '~> 3.13'
gem 'sqlite3', '~> 2.0'
