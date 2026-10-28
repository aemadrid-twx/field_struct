---
title: Declared failures, skips and typed outcomes
description: "fails, skips, their metadata and strictness, GEM_FAILURE_CODES, per-code output schemas and typed_outcomes."
sidebar:
  order: 5
---

An action can list the failure and skip codes it may end with. The
declarations carry neutral metadata, make the codes strict, and, with a block,
give each code its own output schema.

## API

| Class method | Returns | Meaning |
|---|---|---|
| `fails(code, message = nil, **metadata) { … }` | `declared_failures` | declare a failure code; the block (optional) declares its output schema |
| `skips(code, message = nil, **metadata) { … }` | `declared_skips` | declare a skip code, same shape |
| `declared_failures` / `declared_skips` | `{code => metadata}` | the declarations' metadata |
| `failure_declarations` / `skip_declarations` | `{code => {message:, metadata:}}` | the full entries; an entry also has `output_schema:` when the code declares one |
| `allows_failure_code?(code)` | Boolean | `true` when nothing is declared, the code is declared, or it is in `GEM_FAILURE_CODES` |
| `allows_skip_code?(code)` | Boolean | `true` when nothing is declared or the code is declared |
| `failure_output_schema(code)` / `skip_output_schema(code)` | Class or `nil` | the code's output schema |
| `typed_outcomes(enabled: true)` / `typed_outcomes?` | Boolean | turn typed outcomes on or off, read the setting |

Declarations are inherited (copied when the subclass is defined). A subclass can
add codes, and redeclaring a code replaces its message, metadata and schema.

## Declared failures

The keywords after the message are metadata: the gem stores them, attaches them
to the failure as `result.metadata` and shows them in `describe`, but never reads
them. The declared message is used when the `fail` call gives none.

```ruby run
class Charge < Actionable::Action
  fails :refused, 'the card was refused', kind: :rejected
  fails :not_found, kind: :not_found

  step :charge
  def charge = fail!(:refused, nil, kind: 'is not a known kind')
end

result = Charge.run
result.code            # => :refused
result.message         # => "the card was refused"
result.metadata        # => { kind: :rejected }
result.errors[:kind]   # => ["is not a known kind"]
Charge.declared_failures      # => { refused: { kind: :rejected }, not_found: { kind: :not_found } }
Charge.failure_declarations   # => { refused: { message: "the card was refused", metadata: { kind: :rejected } }, not_found: { message: nil, metadata: { kind: :not_found } } }
```

A failure whose code is not declared has `metadata == {}`.

### Strict once declared

An action that declares at least one failure may only fail with codes it
declares. Any other `fail` / `fail!` / `fail_with` / `fail_with!` raises
`Actionable::DefinitionError` at the call:

```ruby run
class Refund < Actionable::Action
  fails :refused, kind: :rejected
  step :go
  def go = fail!(:timeout)
end

begin
  Refund.run
rescue Actionable::DefinitionError => e
  e.message   # => "Refund fails with :timeout, which it does not declare; declare it with `fails :timeout` (declared: :refused)"
end
```

Exempt:

- actions that declare no failures
- the codes the gem emits itself:

```ruby run
Actionable::Action::GEM_FAILURE_CODES   # => [:invalid_input, :invalid_output]
```

Declaring a gem code only attaches metadata to the failures the gem builds.
`fail_with`'s default `:invalid` is _not_ exempt. A nested action's failure
becomes the parent's own, so a declaring parent must declare its children's
failure codes.

## Declared skips

`skips` has the same shape as `fails`:

```ruby run
class SyncField < Actionable::Action
  skips :not_ready, 'the field is not created yet', retry: true
  skips :already_synced, retry: false

  step :sync
  def sync = skip!(:not_ready)
end

result = SyncField.run
result.skipped?   # => true
result.code       # => :not_ready
result.message    # => "the field is not created yet"
result.metadata   # => { retry: true }
SyncField.declared_skips   # => { not_ready: { retry: true }, already_synced: { retry: false } }
```

Strictness has no exemptions: the gem emits no skips of its own, and `skip`'s
implicit default `:skipped` is an undeclared code like any other.

```ruby run
class Archive < Actionable::Action
  skips :already_archived
  step :go
  def go = skip!
end

begin
  Archive.run
rescue Actionable::DefinitionError => e
  e.message.include?('skips with :skipped, which it does not declare')   # => true
end
```

Declared failures and declared skips are independent: declaring one never makes
the other strict. A child's skip never becomes the parent's outcome, so a parent
doesn't declare its children's skip codes.

## Typed outcomes

A block on `fails` or `skips` declares the output a result with that code
carries, in the [`output`](../input-and-output/#output) DSL and with the same
reserved-name check. `typed_outcomes` (opt-in, inherited) makes every skip and
failure follow its code's schema and gives the action its own result classes.

```ruby run
class ActivateKey < Actionable::Action
  typed_outcomes
  input  { required :id, :integer }
  output { required :id, :integer }

  skips(:already_active) { required :id, :integer }
  fails(:invalid) { optional :field, :string }

  step :activate

  def activate
    return skip!(:already_active, nil, id: input.id) if input.id == 1
    return fail!(:invalid, 'bad id', output: { field: 'id' }, id: 'is negative') if input.id.negative?

    @id = input.id
  end
end

skipped = ActivateKey.run(id: 1)
skipped.class          # => ActivateKey::Skipped
skipped.id             # => 1
failed = ActivateKey.run(id: -1)
failed.class           # => ActivateKey::Failure
failed.output.field    # => "id"
failed.errors[:id]     # => ["is negative"]
ActivateKey.run(id: 2).class                        # => ActivateKey::Success
ActivateKey.typed_outcomes?                         # => true
ActivateKey.skip_output_schema(:already_active).attribute_names   # => [:id]
```

The rules:

| Case | Behaviour |
|---|---|
| a code **with** a schema (typed outcomes on or off) | output built from the verb's keywords only, never instance variables, and validated; breaking the schema ends the run as `invalid_output` |
| a code **without** a schema, typed outcomes on | empty output (`{}`) |
| a code without a schema, typed outcomes off | best-effort capture into the success schema, as before |
| `invalid_input` / `invalid_output` | keep the struct that explains them, either way |
| output keywords for a code without a schema, typed outcomes on | `Actionable::DefinitionError` naming the code |
| `output:` that is not a Hash or a FieldStruct | `ArgumentError` |
| `fail` / `fail!` | `output:` is reserved as the failure's output (typed outcomes only) |
| `fail_with` / `fail_with!` | take `output:` as a keyword; `ArgumentError` without typed outcomes |

Without typed outcomes only `skip` can supply output to a schema. A `fails`
schema with required fields needs `typed_outcomes`. There `output:` is just
another error field, so the failure's output stays empty and breaks the schema:

```ruby run
class RejectKey < Actionable::Action
  fails(:bad) { required :id, :integer }
  step :reject
  def reject = fail!(:bad, output: { id: 1 })
end

RejectKey.typed_outcomes? # => false
RejectKey.run.code        # => :invalid_output
```

`.run` returns the action's own `Success`, `Failure` and `Skipped`, constants
defined inside it. Each subclasses the gem class, or the parent action's own
class for a subclass, so `result.is_a?(Actionable::Failure)` still holds. An
action that already has its own constant by one of those names raises
`DefinitionError` when it turns typed outcomes on. A host's own result subclass
is returned as it is.

```ruby run
ActivateKey.run(id: 1).is_a?(Actionable::Skipped)   # => true
ActivateKey::Failure.superclass                      # => Actionable::Failure
```

A nested failure that crosses into a typed parent becomes the parent's own
`Failure`. Its output is judged by the schema the parent declares for the code.
A parent without typed outcomes gets a plain `Actionable::Failure` from a typed child.
`typed_outcomes enabled: false` turns it off again for a subclass.

Results compare by class, so under typed outcomes
`ActivateKey.run(id: 2) == Actionable::Success.new(...)` is false.

Upstream: [USAGE, Declared failures](https://github.com/aemadrid-twx/actionable/blob/v1.10.0/USAGE.md#declared-failures), [Declared skips](https://github.com/aemadrid-twx/actionable/blob/v1.10.0/USAGE.md#declared-skips), [Typed outcomes](https://github.com/aemadrid-twx/actionable/blob/v1.10.0/USAGE.md#typed-outcomes).
