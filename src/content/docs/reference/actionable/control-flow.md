---
title: Control flow
description: "The recording verbs (succeed, fail, fail_with, skip), their bang forms and halt!, the code rule, and where a plain verb may go."
sidebar:
  order: 2
---

Steps and hooks decide the outcome with a few private instance methods. Plain
verbs record a result and keep running; bang verbs record it and stop. Stopping
uses `throw`/`catch`, never an exception.

## The verbs

| Verb | Records | Stops the pipeline? | Returns |
|---|---|---|---|
| `succeed(message = nil, **output)` | `Success` | no | `true` |
| `fail(code, message = nil, **errors)` | `Failure` | no | `false` |
| `fail_with(source, code: :invalid, message: nil, output: nil)` | `Failure` absorbing `source.errors` | no | `false` |
| `skip(code = :skipped, message = nil, **output)` | `Skipped` | no | `false` |
| `succeed!` / `fail!` / `fail_with!` / `skip!` | as the plain verb, same arguments | **yes** | — |
| `halt!` | nothing; keeps the current result | **yes** | — |

- `succeed`'s keywords become the result's `output`; with a declared
  [output schema](../input-and-output/#output) they overlay the captured instance
  variables.
- `fail`'s keywords become the result's `errors`: each is a field and one message
  or an Array of messages. Nothing else follows the message, so an error on a
  field named like metadata (`kind:`) stays an error. Under
  [typed outcomes](../declared-outcomes/#typed-outcomes), `output:` is reserved
  as the failure's output.
- `skip`'s keywords become the skip's output: captured best-effort, never
  validated (unless the code declares an output schema).
- `fail_with`'s `output:` is only allowed under typed outcomes; otherwise it
  raises `ArgumentError`.
- A `halt!` with no recorded result lets the run auto-succeed.

### Last write wins

Plain verbs don't stop later steps. The final result is the most recent one
recorded, or `Success` if none was:

```ruby run
class LastWins < Actionable::Action
  step :a
  step :b
  def a = fail(:nope)
  def b = succeed('recovered')
end

LastWins.run.success?   # => true
LastWins.run.message    # => "recovered"
```

```ruby run
class Stops < Actionable::Action
  step :check
  step :finish
  def check  = fail!(:card_expired, 'card expired', card: 'has expired')
  def finish = succeed
end

result = Stops.run
result.code           # => :card_expired
result.errors[:card]  # => ["has expired"]
```

```ruby run
class HaltOnly < Actionable::Action
  step :a
  step :b
  def a = halt!
  def b = fail(:never)
end

HaltOnly.run.code   # => :success
```

### `fail_with`

`fail_with` copies every error of `source` (anything with a FieldStruct-style
`errors`) into the failure. It's how the gem builds `:invalid_input` and
`:invalid_output`, exposed for validating a side struct:

```ruby run
EventShape = Class.new(FieldStruct::Base) { required :event_type, :string }

class Ingest < Actionable::Action
  step :validate
  def validate = fail_with!(EventShape.new, code: :invalid_event)
end

result = Ingest.run
result.code                 # => :invalid_event
result.errors[:event_type]  # => ["is required"]
```

## Codes must be identifiers

A `fail` / `fail_with` / `skip` code must be a Symbol or String matching
`Actionable::Action::CODE_FORMAT`: letters, digits and underscores, not starting
with a digit, optionally ending in `?` or `!`. Strings are converted to Symbols.

```ruby run
Actionable::Action::CODE_FORMAT.match?('card_expired')   # => true
Actionable::Action::CODE_FORMAT.match?('ok?')            # => true
Actionable::Action::CODE_FORMAT.match?('card expired')   # => false
```

Inside an action, `fail` is `Actionable::Action#fail`, not Ruby's `Kernel#fail`
(the alias of `raise`). A sentence is almost always meant as `raise`, so it
raises `ArgumentError` at the call:

```ruby run
class Habit < Actionable::Action
  step :check
  def check = fail('card expired')
end

begin
  Habit.run
rescue ArgumentError => e
  e.message.start_with?('Habit: failure code "card expired" is not an identifier')   # => true
end
```

A one-word string (`fail 'boom'`) is a valid code, so it records a failure
`:boom`. Code outside an action still gets `Kernel#fail`. Once an action
[declares failures or skips](../declared-outcomes/), an undeclared code raises
`DefinitionError` at the call too.

## Where a plain verb may go

Because plain verbs keep running, `fail :card_expired if card.expired?` followed
by `notify` still notifies. The rule: **in a step or hook method, a plain
recording verb must be the method's last expression, or explicitly end it.**
Bang verbs can go anywhere.

On an action's first run, every step method (case-step branch targets included)
and hook method (`on_success` / `on_failure` / `on_skip` / `always`, and
`after_commit` with the Rails adapter) is parsed with Prism. A misplaced verb
raises `DefinitionError` naming the action, method, `file:line` and verb, and
suggesting the bang form. The check runs once per class; a failing check raises
on every run until it's fixed.

```ruby run
class Leaky < Actionable::Action
  step :charge

  def charge
    fail :card_expired if true
    @charged = true
  end
end

begin
  Leaky.run
rescue Actionable::DefinitionError => e
  e.message.include?('calls `fail` with more code after it, which still runs: use fail! to stop here')   # => true
end
```

| The verb call (`fail`, `fail_with`, `skip`, `succeed`, or `self.fail` …) | |
|---|---|
| is the method's last statement (a modifier `fail :x if bad?` counts as the statement) | OK |
| is the last statement of an `if` / `elsif` / `else` / `unless` / ternary / `case`-`when` / `case`-`in` / `rescue` / `ensure` branch, or the right side of `&&` / `and` / `\|\|` / `or`, whose construct is itself last | OK |
| is returned: `return fail(:x) if bad?`, or followed directly by `return` | OK |
| is the last statement of a block or loop body (or followed directly by `next` / `break`), and the block's call is itself last | OK |
| is followed by an `ensure` | OK |
| has another receiver (`gateway.fail`, `items.skip(1)`) | not checked |
| is followed by more code in the method, a branch whose construct is followed by more code, or a begin body that has an `else` | **offense** |
| is the end of a block or loop body whose call is followed by more code | **offense** |
| is the left side of `and` / `or`: `fail(:x) and return` never returns (`fail` returns `false`) | **offense** |
| is nested in a larger expression: `log(fail(:x))`, `@ok = fail(:x)` | **offense** |

The check is skipped where it can't be done: without Prism (Ruby 3.2 without the
`prism` gem), or without readable source (a method from `eval` or
`define_method`). Helper methods that steps call aren't checked. Switch it off
with `Actionable.verb_position_check = false`
([details](../actions-and-steps/#turning-the-verb-position-check-off)); the
[RuboCop cop](../rubocop/) applies the same rules as a lint.

Upstream: [USAGE, Control flow](https://github.com/Paymentbox-com/actionable/blob/v1.10.0/USAGE.md#control-flow).
