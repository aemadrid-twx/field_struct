---
title: Results
description: "Actionable::Result, Success, Failure and Skipped: attributes, defaults, predicates, status, to_h, to_api_h, metadata and output delegation."
sidebar:
  order: 3
---

Every run returns one result. `Actionable::Result` is a `FieldStruct::Base`
subclass with three concrete subclasses: `Actionable::Success`,
`Actionable::Failure` and `Actionable::Skipped`. You can build them directly,
which is handy in tests.

```ruby run
ok = Actionable::Success.new(message: 'done')
ok.success?   # => true
ok.ok?        # => true

skipped = Actionable::Skipped.new(code: :not_ready)
skipped.skipped?   # => true
skipped.failure?   # => false
skipped.ok?        # => true

bad = Actionable::Failure.new(code: :nope)
bad.failure?   # => true
bad.ok?        # => false
```

## Attributes

| Attribute | Type | Default | Notes |
|---|---|---|---|
| `code` | `:symbol`, required | `Success`: `:success`; `Failure`: `:error`; `Skipped`: `:skipped` | the outcome's code |
| `message` | `:string`, optional | `nil` | human-readable text |
| `output` | `:value` | `{}` | the typed output struct when the action declares one, else a Hash |
| `history` | `:value` | `[]` | a [`History`](../hooks-and-history/#history) when the run was measured |
| `metadata` | `:value` (`Failure` and `Skipped` only) | `{}` | the [declared metadata](../declared-outcomes/) for the code |
| `errors` | `FieldStruct::Errors` | empty | the struct's own errors collection, used for the failure's errors |

`errors` is FieldStruct's collection, so `errors[:field]`, `errors.to_h`,
`errors.add` and `errors.full_messages` all work:

```ruby run
failure = Actionable::Failure.new(code: :invalid)
failure.errors.add(:first_name, 'is required')

failure.code                    # => :invalid
Actionable::Failure.new.code    # => :error
failure.errors.full_messages    # => ["First name is required"]
```

## Predicates and status

| Method | `Success` | `Failure` | `Skipped` |
|---|---|---|---|
| `success?` / `successful?` | `true` | `false` | `false` |
| `failure?` / `failed?` | `false` | `true` | `false` |
| `skipped?` | `false` | `false` | `true` |
| `ok?` (≡ `!failure?`) | `true` | `false` | `true` |
| `status` | `:success` | `:failure` | `:skipped` |

A skip is a strict third state: neither a success nor a failure.

## Hash views

`to_h` renders the result to plain values: `output` through its `to_h`,
`history` through `History#as_json`, `errors` as a Hash. `Failure#to_h` and
`Skipped#to_h` add `metadata`.

`to_api_h(index: nil, id_field: :id)` is a compact element for an HTTP or batch
response: `index`, `status`, the `id` read off the output (by `id_field`), and
`errors`.

```ruby run
class MakeWidget < Actionable::Action
  output { required :id, :integer }
  step :build
  def build = @id = 99
end

result = MakeWidget.run
result.status              # => :success
result.to_h                # => { code: :success, message: nil, output: { id: 99 }, history: [], errors: {} }
result.to_api_h(index: 0)  # => { index: 0, status: :success, id: 99, errors: {} }

Actionable::Failure.new(code: :nope).to_h   # => { code: :nope, message: nil, output: {}, history: [], errors: {}, metadata: {} }
```

## `inspect` and `to_s`

Both give a compact, deterministic form with the attributes and errors sorted by
name:

```ruby run
Actionable::Success.new.inspect   # => "#<Actionable::Success code=:success errors={} history=[] message=nil output={}>"
```

## Reading output off the result

When the action declares an output schema, each declared field can be read off
the result directly: `result.total` is `result.output.total`. This goes through
`method_missing`, so a field whose name is already a method on the result
(`status`, `ok?`, `to_h`, …) is not delegated; read it from `result.output`.
Names that collide with the result's attributes can't be declared at all
([reserved names](../input-and-output/#reserved-output-names)).

```ruby run
class Activate < Actionable::Action
  output do
    required :total,  :integer
    optional :status, :string
  end
  step :go
  def go = (@total = 3; @status = 'active')
end

result = Activate.run
result.total           # => 3
result.status          # => :success
result.output.status   # => "active"
```

## Equality

Results are FieldStructs, so two results of the same class with the same
attributes are `==`. Under [typed outcomes](../declared-outcomes/#typed-outcomes)
`.run` returns the action's own result classes, so a comparison with a gem
`Actionable::Success` is false.

```ruby run
Actionable::Success.new(message: 'm') == Actionable::Success.new(message: 'm')   # => true
```

Upstream: [USAGE, Results](https://github.com/aemadrid-twx/actionable/blob/v1.10.0/USAGE.md#results) and [Serializing a result](https://github.com/aemadrid-twx/actionable/blob/v1.10.0/USAGE.md#serializing-a-result).
