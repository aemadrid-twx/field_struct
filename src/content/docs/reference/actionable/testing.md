---
title: Testing
description: "actionable/rspec: the perform_actionable matcher, result builders and stubs; actionable/rspec/coverage: outcome coverage and its baseline."
sidebar:
  order: 10
---

## RSpec support

`require 'actionable/rspec'` (never loaded by the core) defines
`Actionable::RSpec::Matchers` and `Actionable::RSpec::Stubs`. When `RSpec` is
defined, it includes both into every example group.

### `perform_actionable`

`perform_actionable(*args, **kwargs)` runs the action under test with those
arguments. `expect(MyAction).to perform_actionable(...)` then checks the
outcome. With no chained call it expects a success.

| Chain | Passes when |
|---|---|
| `.and_succeed(message = nil)` | a `Success` |
| `.and_fail(code = nil, message = nil)` | a `Failure`, with that code when given |
| `.and_skip(code = nil, message = nil)` | a `Skipped`, with that code when given |
| `.and_raise(error_class = StandardError, message = nil)` | `.run` raised an `error_class` |

- A message is compared with `===`, so a String or a Regexp works.
- Each chain also takes a block, called with `(result, exception)`. The matcher
  passes only if the block returns truthy.
- `.run` is called inside a `rescue StandardError`, so an unexpected exception
  fails a non-`and_raise` expectation, and the failure message shows it with its
  backtrace. Set `ACTIONABLE_SHORT_BACKTRACE` to trim the backtrace to
  `ACTIONABLE_BACKTRACE_QTY` frames (default 10).
- On an action that declares failures (or skips), `and_fail` (or `and_skip`)
  with an undeclared code raises `ArgumentError`, since it would test an outcome
  the action can never return. A bare `and_fail` / `and_skip` is always accepted.

The matcher is a plain object, so it also works outside RSpec:

```ruby run
require 'actionable/rspec'
include Actionable::RSpec::Matchers

class Decline < Actionable::Action
  fails :refused
  step :charge
  def charge = fail!(:refused, 'the card was refused')
end

perform_actionable.and_fail(:refused).matches?(Decline)            # => true
perform_actionable.and_fail(:refused, /refused/).matches?(Decline)  # => true

matcher = perform_actionable.and_succeed
matcher.matches?(Decline)   # => false
matcher.failure_message.start_with?('expected Decline to succeed, but got #<Actionable::Failure')   # => true

begin
  perform_actionable.and_fail(:timeout).matches?(Decline)
rescue ArgumentError => e
  e.message   # => "Decline does not declare :timeout (declared: :refused); a stub or and_fail with it tests a failure the action can never return"
end
```

In a spec:

```ruby
RSpec.describe Decline do
  it { expect(described_class).to perform_actionable.and_fail(:refused, 'the card was refused') }
  it { expect(Charge).to perform_actionable(amount: 5).and_succeed { |result, _| result.output.id } }
end
```

### Building results

These build real results without running or stubbing anything:

| Helper | Default code |
|---|---|
| `actionable_success_result(message: nil, output: {}, errors: {})` | `:success` |
| `actionable_failure_result(code: :error, message: nil, output: {}, errors: {}, metadata: {})` | `:error` |
| `actionable_skip_result(code: :skipped, message: nil, output: {}, metadata: {})` | `:skipped` |

```ruby run
include Actionable::RSpec::Stubs

failure = actionable_failure_result(code: :refused, errors: { card: 'was refused' })
failure.code           # => :refused
failure.errors[:card]  # => ["was refused"]
actionable_skip_result.code   # => :skipped
```

### Stubbing `.run`

These need rspec-mocks (they call `allow` / `expect`), so they only work inside a
spec. Each makes `Action.run` return a result built from the keywords, without
running the action, and returns that result.

| Helper | rspec-mocks call | Keywords |
|---|---|---|
| `allow_actionable_success(action, **opts)` / `stub_actionable_success` | `allow` / `expect … to receive(:run)` | as `actionable_success_result` |
| `allow_actionable_failure(action, **opts)` / `stub_actionable_failure` | same | as `actionable_failure_result`; `code:` defaults to `:error` |
| `allow_actionable_skip(action, **opts)` / `stub_actionable_skip` | same | as `actionable_skip_result`; `code:` defaults to `:skipped` |

```ruby
allow_actionable_failure(Charge, code: :refused)
expect(Checkout.run(cart: cart).code).to eq(:refused)
```

- A stubbed failure or skip carries the declared metadata of its code, and the
  declared message when you give none.
- On an action that declares failures (or skips), a stub with an undeclared code
  raises `ArgumentError`. `GEM_FAILURE_CODES` are exempt for failures. Nothing is
  exempt for skips, so `allow_actionable_skip(action)` with no `code:` raises
  unless the action declares `:skipped`.
- The output is shaped as a real run would shape it. It goes through the code's
  output schema when it has one (an `ArgumentError` when it breaks the schema).
  Under typed outcomes, it is empty for a code without one (an `ArgumentError`
  when you give output for it). Under typed outcomes the helpers return the action's own result
  classes.

## Outcome coverage

`require 'actionable/rspec/coverage'` records every real `.run` of a named action
as `[class name, outcome, code]`. At the end of the suite, it reports each
action's declared outcomes that no spec reached. Neither the core nor
`actionable/rspec` loads it.

An action's expected outcomes are outcome keys: `"success"` always, plus
`"failure:<code>"` for each declared failure and `"skipped:<code>"` for each
declared skip.

```ruby run
require 'actionable/rspec/coverage'

class SyncLater < Actionable::Action
  skips :not_ready
  step :sync
  def sync = nil
end

SyncLater.run

Actionable::Coverage.expected_outcomes(SyncLater)   # => ["success", "skipped:not_ready"]
Actionable::Coverage.observed.include?(['SyncLater', :success, :success])   # => true

report = Actionable::Coverage::Report.new
report.to_baseline['SyncLater']   # => ["skipped:not_ready"]
report.totals[:missing] >= 1      # => true
```

Nested action runs and `run_each` items count. A stubbed `.run` never counts.
The gem's stub helpers note their results in `Coverage.stubbed`, shown as
"Stubbed only".

A typical setup:

```ruby
# spec/support/actionable_coverage.rb
require 'actionable/rspec/coverage'

Actionable::Coverage.loader   = -> { Rails.application.eager_load! }
Actionable::Coverage.baseline = 'spec/actionable_coverage_baseline.yml'
```

### Settings

All on `Actionable::Coverage`; `reset_config!` restores the defaults.

| Setting | Default | Meaning |
|---|---|---|
| `root` | `Actionable::Action` | report its named descendants (found through `subclasses`) that have steps; anonymous classes, classes with no steps and classes whose name no longer resolves to them are left out |
| `include_prefixes` / `exclude_prefixes` | `[]` | name filters: a String matches as a prefix, a Regexp by `match?` |
| `loader` | `nil` | called before the actions are listed, e.g. to eager-load a Rails app |
| `gem_codes` | `[]` | gem codes to expect too (only `:invalid_input`, `:invalid_output`; anything else raises `ArgumentError`). `:invalid_input` counts for an action whose input has a required field (or whose `input_for` has no default); `:invalid_output` for one whose success, skip or failure schema has a required field |
| `only_observed` | `false` | report only actions with at least one real run |
| `baseline` | `nil` | path to a JSON or YAML file of known gaps |
| `new_gap_hint` | `DEFAULT_NEW_GAP_HINT` (`'Write a spec that reaches each one, or add it to the baseline:'`) | the advice after "New untested outcomes." |

Recording: `enable!` (done on require), `disable!`, `enabled?`, `reset!`;
`observed` and `stubbed` hold the runs; `write(path)` / `read(path)` save and load
one process's runs as JSON.

### The report and the baseline

`Actionable::Coverage::Report.new(files: [])` builds the report. `to_s` is a table
of never-reached and stubbed-only outcomes plus totals, and `rows`, `totals`,
`to_h` and `to_json` give the same data to a machine.

```text
Actionable outcome coverage
  Action           Never reached                       Stubbed only
  Billing::Charge  failure:refused, failure:not_found  failure:refused
  Billing::Refund  success
Actions: 2  Expected outcomes: 4  Reached: 1  Missing: 3
```

Missing outcomes alone never fail a suite. With `baseline` set to a file of
`{"Action::Name" => [outcome keys]}`, the report fails when an untested outcome
is not listed. It also fails when a listed one is now covered, no longer declared, or names an
action that is gone. `Report#to_baseline` returns the current gaps in that shape, and
`write_baseline(path = Coverage.baseline)` writes them (YAML for `.yml` / `.yaml`,
JSON otherwise).

`Coverage.report!(files: [], io: $stdout)` prints the report and raises
`Actionable::Coverage::BaselineMismatch` when it disagrees with the baseline.

| Environment variable | Effect |
|---|---|
| `ACTIONABLE_COVERAGE_FILE=path` | at suite end, write this process's runs to `path` instead of reporting (one path per shard) |
| `ACTIONABLE_COVERAGE_JSON=path` | also write the report's JSON there |
| `ACTIONABLE_COVERAGE_UPDATE_BASELINE=true` | rewrite the baseline from the current gaps instead of checking it |

When RSpec is loaded, an `after(:suite)` hook does the above. For a sharded
suite, merge the shard files in a later step with
`Coverage.report!(files: 'tmp/actionable_coverage/*.json')`. A glob that matches
nothing raises `Actionable::Error`. Set `baseline` only for full runs, and use
`only_observed = true` for targeted local runs.

Upstream: [USAGE, RSpec integration](https://github.com/aemadrid-twx/actionable/blob/v1.10.0/USAGE.md#rspec-integration) and [Outcome coverage](https://github.com/aemadrid-twx/actionable/blob/v1.10.0/USAGE.md#outcome-coverage).
