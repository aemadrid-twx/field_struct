---
title: Batches and introspection
description: "run_each and BatchResult; describe, describe_text and Actionable.registry."
sidebar:
  order: 7
---

## Batch runs: `run_each`

`Action.run_each(enumerable) { |item| run_args }` runs the action once per item
and returns an `Actionable::BatchResult`. Each item is its own `.run`, so one
failure never affects another. There is no batch-wide transaction.

The block maps an item to `.run` arguments:

| Block returns | `.run` is called as |
|---|---|
| a Hash | `run(**hash)` |
| an Array | `run(*array)` |
| anything else | `run(value)` |

Without a block, each item goes through the same mapping.

```ruby run
class Doubler < Actionable::Action
  input  { required :n, :integer }
  output { required :doubled, :integer }
  step :go
  def go = @doubled = input.n * 2
end

batch = Doubler.run_each([1, 'x', 3]) { |n| { n: n } }
batch.size           # => 3
batch.all_ok?        # => false
batch.any_failure?   # => true
batch.partial?       # => true
batch.successes.map(&:doubled)   # => [2, 6]
batch.failures.map(&:code)       # => [:invalid_input]
batch.to_api_h.map { |h| h[:status] }   # => [:success, :failure, :success]
```

| `BatchResult` | |
|---|---|
| `results` | the Array of per-item results, in order |
| `each`, `[]`, `size` / `length`, `empty?` | Enumerable over the results |
| `all_ok?` | every result is `ok?` (success or skip) |
| `any_failure?` | at least one failure |
| `partial?` | at least one failure **and** at least one ok |
| `successes` / `failures` / `skips` | the results of each outcome |
| `to_api_h(id_field: :id)` | each result's [`to_api_h`](../results/#hash-views) with its index |

## `describe`

`Action.describe` is a Hash summary of an action, so a human or an agent can
understand it without reading its source.

| Key | Value |
|---|---|
| `:name` | the class name |
| `:input` | the input schema's `metadata.to_h`; for `input_for`, `{discriminated_on:, shapes:}`; `nil` when free-form |
| `:output` | the output schema's `metadata.to_h`, or `nil` |
| `:steps` | `[{type:, name:, options:}]`, where `type` is `:method`, `:action` or `:case` |
| `:failures` / `:skips` | `{code => {message:, metadata:}}`, plus `output:` (the schema's fields) for a code with a schema |
| `:hooks` | `{on_success: [...], on_failure: [...], on_skip: [...], always: [...]}` (the Rails adapter adds `after_commit:`) |
| `:measure` | the measure mode |
| `:transactional` | the Rails adapter's transaction config, else `nil` |

```ruby run
class Probe < Actionable::Action
  fails :refused, 'the card was refused', kind: :rejected
  output { required :count, :integer }
  step :compute
  always :audit
  def compute = @count = 1
  def audit = nil
end

Probe.describe[:steps]      # => [{ type: :method, name: :compute, options: {} }]
Probe.describe[:failures]   # => { refused: { message: "the card was refused", metadata: { kind: :rejected } } }
Probe.describe[:hooks]      # => { on_success: [], on_failure: [], on_skip: [], always: [:audit] }
Probe.describe[:measure]    # => :none
Probe.describe[:input]      # => nil
```

`Action.describe_text` renders the same information as text. The field lines
come from FieldStruct's `Metadata#describe`. `Failures:`, `Skips:` and `Hooks:`
appear only when there are any.

```ruby run
puts Probe.describe_text
Probe.describe_text.lines.first.chomp   # => "Probe (measure: none)"
Probe.describe_text.lines[3].strip      # => "count (Integer, required) — accepts in (Array | Range), base (Integer), strict (TrueClass | FalseClass)"
```

prints:

```text
Probe (measure: none)
  Input: (free-form)
  Output:
    count (Integer, required) — accepts in (Array | Range), base (Integer), strict (TrueClass | FalseClass)
  Steps:
    - compute (method)
  Failures:
    - refused (kind: :rejected): the card was refused
  Hooks:
    always: audit
```

A transactional action's first line reads `(measure: none, transactional)`.

## Registry

Every named subclass of `Actionable::Action` registers itself, keyed by its
class name, when it is defined. A class without a name at that moment
(`Foo = Class.new(Actionable::Action)`) is not registered.

```ruby run
class Registered < Actionable::Action
end

Actionable.registry['Registered'].equal?(Registered)   # => true
Actionable.registry[Registered].equal?(Registered)     # => true
Actionable.registry.keys.include?('Probe')             # => true
```

`Actionable.registry` answers `[]` (a name, or anything whose `to_s` is the
name), `each`, `keys`, `values`, `size` and `empty?`.

Upstream: [USAGE, Batch runs](https://github.com/aemadrid-twx/actionable/blob/v1.10.0/USAGE.md#batch-runs), [Registry](https://github.com/aemadrid-twx/actionable/blob/v1.10.0/USAGE.md#registry), [Introspection](https://github.com/aemadrid-twx/actionable/blob/v1.10.0/USAGE.md#introspection--actiondescribe).
