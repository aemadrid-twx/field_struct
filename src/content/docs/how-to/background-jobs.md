---
title: How to run an action in a background job
description: Run an action from an ActiveJob or Sidekiq job, so failures retry or get discarded based on their code.
sidebar:
  label: Run in a background job
  order: 9
---

You want a job to retry or give up based on why its action failed.
`require 'actionable/job'` adds a mixin for job classes. It runs the action and
turns the result into what the queue should do:

| Result | Disposition | What the mixin does |
|---|---|---|
| success or skip | `:ack` | returns the result |
| failure with a permanent code | `:discard` | returns the result |
| any other failure | `:retry` | raises `Actionable::Job::RetryableFailure` |

The permanent codes are `:invalid_input`, `:invalid_output` and `:not_found`
unless you change them. An exception raised inside the action is never caught,
so the queue retries it as usual.

## 1. Write the action

```ruby title="reindex_document.rb" run
SEARCH = { up: false, docs: [1, 2] }

class ReindexDocument < Actionable::Action
  fails :not_found,   'no such document'
  fails :search_down, 'search cluster unavailable'

  input { required :document_id, :integer }

  step :reindex

  def reindex
    fail!(:not_found) unless SEARCH[:docs].include?(input.document_id)
    fail!(:search_down) unless SEARCH[:up]
    succeed("reindexed #{input.document_id}")
  end
end
```

## 2. Wrap it in a job

Include `Actionable::Job::Mixin` and call `run_actionable` from `perform`. With
ActiveJob, tell it to retry on `RetryableFailure`:

```ruby title="reindex_document_job.rb" run
require 'active_job'
require 'actionable/job'

class ReindexDocumentJob < ActiveJob::Base
  include Actionable::Job::Mixin

  retry_on Actionable::Job::RetryableFailure, wait: 30, attempts: 5

  def perform(document_id)
    run_actionable(ReindexDocument, document_id: document_id)
  end
end
```

With Sidekiq it is the same mixin. Sidekiq retries any job that raises, so no
extra setup is needed:

```ruby
class ReindexDocumentJob
  include Sidekiq::Job
  include Actionable::Job::Mixin

  def perform(document_id) = run_actionable(ReindexDocument, document_id: document_id)
end
```

## 3. Check what happens

This uses ActiveJob's test adapter, so nothing really runs later:

```ruby run
ActiveJob::Base.logger = Logger.new(nil)
ActiveJob::Base.queue_adapter = :test
queue = ActiveJob::Base.queue_adapter

ReindexDocumentJob.perform_now(99).code  # => :not_found
queue.enqueued_jobs.size                 # => 0

ReindexDocumentJob.perform_now(1)        # search is down: :search_down is retryable
queue.enqueued_jobs.size                 # => 1

SEARCH[:up] = true
ReindexDocumentJob.perform_now(1).message  # => "reindexed 1"
```

The `:not_found` failure was discarded, the `:search_down` failure was
re-enqueued by `retry_on`, and the success was acked.

## Choose the permanent codes

Override `actionable_permanent_codes` in the job to say which failure codes a
retry can't fix:

```ruby run
class StrictReindexJob < ReindexDocumentJob
  def actionable_permanent_codes = %i[invalid_input not_found search_down]
end

SEARCH[:up] = false
StrictReindexJob.perform_now(1).code  # => :search_down
queue.enqueued_jobs.size              # => 1
```

To decide per code in the action instead, declare `retry: true` or
`retry: false` as metadata on `fails` and `skips`, and call
`honor_retry_metadata` in the action. See the USAGE link below.

## See also

- actionable USAGE: [Background jobs](https://github.com/aemadrid-twx/actionable/blob/v1.10.0/USAGE.md#background-jobs)
