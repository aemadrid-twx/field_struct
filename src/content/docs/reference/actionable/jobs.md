---
title: Background jobs
description: "actionable/job: Job.disposition, the Mixin for Sidekiq or ActiveJob, RetryableFailure and honor_retry_metadata."
sidebar:
  order: 8
---

`require 'actionable/job'` loads a framework-agnostic helper that runs an
action inside a background job and maps its result to what the queue should do.
The core never loads it. It runs the action synchronously inside `perform`. It
doesn't enqueue anything.

## `Actionable::Job.disposition`

`Actionable::Job.disposition(result, permanent: DEFAULT_PERMANENT_CODES, honor_retry: false)`
returns:

| Result | Disposition |
|---|---|
| `Success` or `Skipped` | `:ack` |
| `Failure` whose code is in `permanent:` | `:discard` |
| any other `Failure` | `:retry` |

```ruby run
require 'actionable/job'

Actionable::Job::DEFAULT_PERMANENT_CODES   # => [:invalid_input, :invalid_output, :not_found]

Actionable::Job.disposition(Actionable::Success.new)                    # => :ack
Actionable::Job.disposition(Actionable::Skipped.new)                    # => :ack
Actionable::Job.disposition(Actionable::Failure.new(code: :not_found))  # => :discard
Actionable::Job.disposition(Actionable::Failure.new(code: :timeout))    # => :retry
Actionable::Job.disposition(Actionable::Failure.new(code: :timeout), permanent: %i[timeout])   # => :discard
```

## `Actionable::Job::Mixin`

Include it in a Sidekiq worker or an ActiveJob job and call `run_actionable`
from `perform`:

```ruby
require 'actionable/job'

class ProjectEventJob
  include Sidekiq::Job              # or: class ProjectEventJob < ActiveJob::Base
  include Actionable::Job::Mixin

  def perform(event_id)
    run_actionable(ProjectApiEvent, event_id: event_id)
  end

  # optional: which failure codes are permanent (not retried)
  def actionable_permanent_codes = %i[invalid_input not_found unprocessable]
end
```

| Mixin method | |
|---|---|
| `run_actionable(action_class, *args, **kwargs)` | runs `action_class.run(*args, **kwargs)`, stores the result, returns it for `:ack` / `:discard`, and raises `RetryableFailure` for `:retry` |
| `actionable_result` | the last result |
| `actionable_permanent_codes` | the `permanent:` set; default `DEFAULT_PERMANENT_CODES`; override it |

A genuine exception inside the action propagates unchanged, so the queue
retries it as it would any error.

`Actionable::Job::RetryableFailure < StandardError` carries the result as
`#result`. Sidekiq retries any raised job by default. Under ActiveJob, declare
`retry_on Actionable::Job::RetryableFailure`.

```ruby run
require 'actionable/job'

class Flaky < Actionable::Action
  step :call_api
  def call_api = fail!(:timeout)
end

class FakeJob
  include Actionable::Job::Mixin
  def perform = run_actionable(Flaky)
end

job = FakeJob.new
error = begin
  job.perform
rescue Actionable::Job::RetryableFailure => e
  e
end

error.message              # => "actionable run failed with retryable code :timeout"
error.result.code          # => :timeout
job.actionable_result.code # => :timeout
```

## Retrying from declared metadata

Declared metadata is neutral by default: `skips :not_ready, retry: true` alone
still acks. An action that calls `honor_retry_metadata` lets the `retry:` key of
its [declared failures and skips](../declared-outcomes/) decide. The macro is
added to `Actionable::Action` by `require 'actionable/job'`, so load the adapter
before defining the action.

| Result | `retry:` truthy | `retry:` present but falsy | no `retry:` key |
|---|---|---|---|
| `Failure` | `:retry` (even a permanent code) | `:discard` (even a transient code) | the default mapping |
| `Skipped` | `:retry` | `:ack` | `:ack` |

`run_actionable` raises `RetryableFailure` for every `:retry`, a retried skip
included. Without a job, pass `honor_retry: true` to `disposition`.

```ruby run
require 'actionable/job'

class Reindex < Actionable::Action
  honor_retry_metadata
  skips :not_ready, retry: true

  step :reindex
  def reindex = skip!(:not_ready)
end

Reindex.honor_retry_metadata?                                 # => true
Actionable::Job.disposition(Reindex.run, honor_retry: true)   # => :retry
Actionable::Job.disposition(Reindex.run)                      # => :ack

class QuietReindex < Reindex
  honor_retry_metadata(enabled: false)
end

QuietReindex.honor_retry_metadata?   # => false
```

`honor_retry_metadata?` is inherited and defaults to `false`. A subclass backs
out with `honor_retry_metadata(enabled: false)`.

Upstream: [USAGE, Background jobs](https://github.com/aemadrid-twx/actionable/blob/v1.10.0/USAGE.md#background-jobs).
