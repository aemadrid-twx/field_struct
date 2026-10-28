---
title: How the two gems fit together
description: actionable orchestrates steps; field_struct does all the typing. Inputs, outputs and results are FieldStructs.
sidebar:
  order: 7
---

actionable is built on field_struct, and the split is strict. actionable runs
steps and decides outcomes. field_struct does every bit of typing, coercion
and validation. It is actionable's invariant 8: "Delegate
typing/validation to FieldStruct. Inputs and outputs are FieldStruct schemas;
we don't reinvent coercion, presence, or `ruby_type`."

## Three places field_struct shows up

**Input.** An `input` block is a FieldStruct declaration. The block builds an
anonymous `FieldStruct::Base` subclass, and `.run` coerces its keywords into
it. Bad input never reaches a step: the run ends as `Failure(:invalid_input)`
with the struct's own errors (D7).

**Output.** An `output` block is the same kind of schema, for what the run
produces (D6).

**Results.** `Success`, `Failure` and `Skipped` are FieldStructs themselves
(D5), so a result has the same `errors`, `attributes` and `inspect` as any
other struct.

```ruby run
class Double < Actionable::Action
  input  { required :n, :integer }
  output { required :doubled, :integer }

  step :double

  def double = @doubled = input.n * 2
end

Double.input.superclass       # => FieldStruct::Base
Double.run(n: '21').doubled   # => 42

bad = Double.run(n: 'lots')
bad.code                      # => :invalid_input
bad.errors.full_messages      # => ["N could not be coerced: Integer fields expect a base-10 integer, got a String that is not one"]

Actionable::Result.ancestors.include?(FieldStruct::Base)  # => true
```

`'21'` became `21` the same way it would in any FieldStruct, and the error
reads the same way too. In other words, everything on the
[coercion vs. validation](../coercion-and-validation/) page applies to an
action's input unchanged.

## Why a declared output

The original actionable surfaced *every* instance variable a run set, through
`method_missing` on the result. The
[first discussion](https://github.com/aemadrid-twx/actionable/blob/v1.10.0/docs/origin/first_discussion.md)
calls that "convenient, but untyped and invisible". The rebuild keeps the
convenience (steps still set `@doubled`), but only fields declared in `output`
are captured: "declaration + ivar name is the contract" (D6). It is
invariant 3: "No 'capture every instance variable' magic."

## Only a success is held to its output

Output is validated through field_struct, but only on a success. D6 explains
why a success that breaks its schema turns into a failure: "the run can't truly
have succeeded, so it becomes a `Failure` with code `:invalid_output`." A
failure or skip is captured best-effort and never validated. Callers should
treat that output as possibly incomplete.

```ruby run
class Forgetful < Actionable::Action
  output { required :total, :integer }
  step :work

  def work = nil
end

result = Forgetful.run
result.code             # => :invalid_output
result.errors[:total]   # => ["is required"]
```

Typed outcomes (D23, opt-in) extend this, so a failure or skip code can
declare a schema of its own.

## The same machinery, as a verb

`:invalid_input` and `:invalid_output` both "absorb" a FieldStruct's errors
into a failure. `fail_with` exposes that for any struct a step builds (D19):

```ruby run
class Shape < FieldStruct::Base
  required :event_type, :string
end

class Ingest < Actionable::Action
  step :check

  def check = fail_with!(Shape.new, code: :invalid_event)
end

Ingest.run.errors[:event_type]   # => ["is required"]
```

## Types all the way down

The schemas are FieldStructs, so the type signatures come from field_struct
too. `Actionable::RBS.generate` types an action's `.run` and its output
readers with `FieldStruct::RBS.type_for`, "so they match what
`FieldStruct::RBS.generate` emits for a named struct" (USAGE, "RBS for your
actions").

## Beyond the two gems

Formats and tools outside Ruby, like JSON Schema, Avro and OpenTelemetry,
connect through separate [adapter gems](/field_struct/adapters/), so an app loads
only the ones it uses. [How adapters work](/field_struct/adapters/how-adapters-work/)
explains the split.

## Related

- [Validity is computed on assignment](../validity-on-assignment/)
- [Success, failure, skip](../three-outcomes/)
- [USAGE: Input](https://github.com/aemadrid-twx/actionable/blob/v1.10.0/USAGE.md#input)
  and [Output](https://github.com/aemadrid-twx/actionable/blob/v1.10.0/USAGE.md#output)
