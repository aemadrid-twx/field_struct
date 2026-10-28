---
title: Input and output
description: "Typed input (input, input_for), typed output (output), :invalid_input and :invalid_output, and the reserved output names."
sidebar:
  order: 4
---

Both schemas are written in the FieldStruct DSL (`required`, `optional`, types
and options; see the field_struct reference). Each block builds an anonymous
`FieldStruct::Base` subclass.

| Class method | With a block | Without a block |
|---|---|---|
| `input { … }` | declares the input schema | returns it (`nil` when none); also `input_schema` |
| `input_for(discriminator) { … }` | declares a discriminated input | — (`input_dispatch` reads it) |
| `output { … }` | declares the output schema | returns it (`nil` when none); also `output_schema` |

## Input

With an `input` block, `.run` takes keyword arguments (or one already-built
instance of the input schema), coerces them into the struct and exposes it to
steps as `input`:

```ruby run
class Double < Actionable::Action
  input  { required :n, :integer }
  output { required :doubled, :integer }
  step :go
  def go = @doubled = input.n * 2
end

Double.run(n: '21').doubled            # => 42
Double.run(Double.input.new(n: 4)).doubled   # => 8
```

A missing or uncoercible required input returns a `Failure` without running any
step:

```ruby run
result = Double.run
result.code         # => :invalid_input
result.message      # => "input failed validation"
result.errors[:n]   # => ["is required"]
```

The input struct follows its own FieldStruct settings, so unknown keywords are
dropped unless the schema says `unknown_attributes :raise`. Typed input is
keyword-only; positional arguments are not mapped to fields.

### Discriminated input (`input_for`)

`input_for(discriminator) { … }` picks the input schema at run time from the
value of one keyword. The block uses the same builder and the same matching as
[`case_step`](../actions-and-steps/#case-steps) (`==`, Array membership, Regexp
on `to_s`):

| Builder method | Meaning |
|---|---|
| `on value, Schema` | use `Schema` when the discriminator matches |
| `default Schema` | use `Schema` when nothing matches |

The chosen schema gets all the keywords, the discriminator included. With no
match and no `default`, the run is `Failure(:invalid_input)`. An instance of any
branch's schema can be passed instead of keywords.

```ruby run
SaleShape   = Class.new(FieldStruct::Base) { required :amount, :integer }
RefundShape = Class.new(FieldStruct::Base) { required :original_id, :integer }

class Capture < Actionable::Action
  input_for :event_type do
    on 'sale',   SaleShape
    on 'refund', RefundShape
  end
  output { optional :amount, :integer }
  step :capture
  def capture
    @amount = input.amount if input.respond_to?(:amount)
  end
end

Capture.run(event_type: 'sale', amount: '5').amount   # => 5
Capture.run(event_type: 'wat').code                   # => :invalid_input
Capture.run(event_type: 'wat').message                # => "no input shape for event_type \"wat\""
```

### Free-form input

With neither block, `.run`'s arguments go to the action's own `initialize`
([example](../actions-and-steps/#run)), and `input` is `nil`.

## Output

`output { … }` declares the typed payload of a success. At the end of the run,
and again after each lifecycle hook, the runner reads the instance variables
named like declared fields. It overlays any `succeed` keywords (keywords win) and
builds the struct:

```ruby run
class Calc < Actionable::Action
  output { optional :total, :integer }
  step :compute
  step :finish
  def compute = @total = 1
  def finish  = succeed(total: 99)
end

Calc.run.output.total   # => 99
Calc.run.total          # => 99
```

Only declared fields are captured; other instance variables never reach the
result.

### Validation is for successes only

| Outcome | Output |
|---|---|
| `Success` | built and validated; if invalid, the run becomes `Failure(:invalid_output)` carrying the struct's errors and the invalid struct as its output |
| `Failure` / `Skipped` (no output schema for the code) | captured best-effort into the success schema, never validated |
| `Failure(:invalid_input)` / `Failure(:invalid_output)` | keeps the struct that explains it |
| a code with its own output schema | built from the verb's keywords only and validated; see [typed outcomes](../declared-outcomes/#typed-outcomes) |

```ruby run
class NeedsTotal < Actionable::Action
  output { required :total, :integer }
  step :noop
  def noop = nil
end

result = NeedsTotal.run
result.code             # => :invalid_output
result.message          # => "output failed validation"
result.errors[:total]   # => ["is required"]
```

### Without an output schema

A free-form action's `output` is whatever was recorded: the `succeed` (or
`skip`) keywords as a Hash, default `{}`. Nothing is captured, coerced or
delegated.

```ruby run
class Loose < Actionable::Action
  step :go
  def go = succeed('ok', total: 3, note: 'any key')
end

Loose.run.output   # => { total: 3, note: "any key" }
```

### Reserved output names

An output field named like a result attribute or a reserved instance variable
raises `Actionable::DefinitionError` when declared. The list is the constant
`RESERVED_OUTPUT_FIELDS`, defined on `Actionable::Action`'s singleton class (so
`Actionable::Action::RESERVED_OUTPUT_FIELDS` is a `NameError`):

```ruby run
Actionable::Action.singleton_class::RESERVED_OUTPUT_FIELDS   # => [:code, :message, :output, :history, :errors, :metadata, :result, :input]

begin
  Class.new(Actionable::Action) { output { optional :metadata, :string } }
rescue Actionable::DefinitionError => e
  e.message   # => "action: output field(s) :metadata conflict with reserved result attributes / instance variables; rename them"
end
```

The same check applies to the output blocks of `fails` and `skips`. Input
fields are not checked: they are read as `input.x`.

Upstream: [USAGE, Output](https://github.com/aemadrid-twx/actionable/blob/v1.10.0/USAGE.md#output) and [Input](https://github.com/aemadrid-twx/actionable/blob/v1.10.0/USAGE.md#input).
