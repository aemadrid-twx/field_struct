---
title: Actions and steps
description: "Actionable::Action, .run, and the step DSL: step, case_step, guards, nested actions, redeclaration and the run-start checks."
sidebar:
  order: 1
---

An action is a subclass of `Actionable::Action`. You list its steps, write each
step as an instance method, and call `.run`, which returns one
[result](../results/). The gem is published as `actionable-rb` and required as
`actionable`.

```ruby run
class Greet < Actionable::Action
  step :build
  step :shout

  def build = @text = 'hello'
  def shout = succeed(@text.upcase)
end

Greet.run.message   # => "HELLO"
Greet.run.success?  # => true
```

A run with no explicit outcome succeeds: if no step calls `succeed`, `fail` or
`skip`, the result is a `Success` with code `:success`.

## `.run`

`Action.run(*args, **kwargs)` builds an instance, checks it, runs the steps and
hooks, and returns the result.

| The action declares | What `.run` does with its arguments |
|---|---|
| an [`input`](../input-and-output/#input) schema | coerces the keywords (or a single input-schema instance) into the input struct; an invalid input returns `Failure(:invalid_input)` without running any step |
| [`input_for`](../input-and-output/#discriminated-input-input_for) | picks the schema from the discriminator keyword, then the same |
| neither (free-form) | passes them to the action's own `initialize` |

The default `initialize` accepts and ignores any arguments, so a free-form
action without a constructor still runs:

```ruby run
class Add < Actionable::Action
  def initialize(a, b:)
    super()
    @a = a
    @b = b
  end

  step :sum
  def sum = succeed(nil, total: @a + @b)
end

Add.run(1, b: 2).output   # => { total: 3 }
```

Genuine exceptions are never caught: a `StandardError` raised in a step
propagates out of `.run`.

## Step DSL

| Macro | Declares |
|---|---|
| `step :name, **options` | a method step: calls the instance method `name` |
| `step OtherAction, **options` | an action step: runs another action (see [Nested actions](#nested-actions)) |
| `case_step :value_method, **options do … end` | a branching step (see [Case steps](#case-steps)) |
| `on_success` / `on_failure` / `on_skip` / `always` | lifecycle hooks, see [Hooks and history](../hooks-and-history/) |

`step` takes a Symbol or String (a method) or an `Actionable::Action` subclass.
Anything else raises `ArgumentError` (`unsupported step target: 5`). Steps run in
declaration order.

Step, hook and case-step methods may be private; they're called with `__send__`.
`Action.steps` returns the declared steps as an ordered `Set`.

### Guards: `if:` and `unless:`

Every step, hook, case step and case branch takes `if:` and `unless:`. A guard is
a Symbol (or String) naming an instance method (which may be private), or a
callable that receives the instance. The step is skipped when `if:` is falsy or
`unless:` is truthy.

```ruby run
class Guarded < Actionable::Action
  output { optional :ran, :array, of: :symbol }

  step :first
  step :second, if: :ready?
  step :third,  unless: ->(action) { action.send(:ready?) }

  def first  = (@ran = [:first])
  def second = (@ran += [:second])
  def third  = (@ran += [:third])

  private

  def ready? = false
end

Guarded.run.ran   # => [:first, :third]
```

### Redeclaring a step

Steps are kept in a `Set` keyed by type and name. Declaring the same step again,
in the same class or a subclass, replaces it: **the last declaration wins and
keeps the first one's position**. A subclass's change never touches the parent.

```ruby run
class Checkout < Actionable::Action
  step :load
  step :charge
end

class DryCheckout < Checkout
  step :charge, if: :live?
end

DryCheckout.steps.map(&:name)        # => [:load, :charge]
DryCheckout.steps.to_a.last.options  # => { if: :live? }
Checkout.steps.to_a.last.options     # => {}
```

| Redeclared with | Result |
|---|---|
| `step :x` then `step :x, if: :ok?` | one `:x` step, guarded, at the first `:x`'s position |
| `step Child` then `step Child, expose: []` | one nested step with the last options |
| `case_step(:x) { … }` twice | one case step with the last block's branches |
| `on_success :x` then `on_success :x, if: :ok?` (same for the other hooks) | one hook with the last options, at the first position |
| `step :x` and `case_step :x` | **two** steps: a method step and a case step are different types |

Each hook phase is its own list, so `on_success :x` and `always :x` are two
hooks. There's no way to remove an inherited step or hook; guard it off instead.

### Inheritance

A subclass gets a copy of its parent's steps, hooks, `input`/`output` schemas,
`input_for`, declared failures and skips, `measure` setting and `typed_outcomes`
setting at the moment it's defined, and can add to or override them.

## Case steps

`case_step value_source do … end` reads a value from an instance method and runs
the first matching branch.

| Builder method | Meaning |
|---|---|
| `on value, target, **options` | run `target` when the value matches |
| `default target, **options` | run `target` when nothing matches |

A target is any step target (a method name or an action class). Matching:

| Branch value | Matches when |
|---|---|
| an Array | `array.include?(value)` |
| a Regexp | `regexp.match?(value.to_s)` |
| anything else | `branch_value == value` |

Branches are tried in order. With no match and no `default`, the case step does
nothing.

```ruby run
class Route < Actionable::Action
  input  { required :kind, :string }
  output { optional :picked, :string }

  case_step :kind do
    on 'a',     :pick_a
    on %w[b c], :pick_bc
    on(/\Az/,   :pick_z)
    default     :pick_default
  end

  def kind         = input.kind
  def pick_a       = @picked = 'a'
  def pick_bc      = @picked = 'bc'
  def pick_z       = @picked = 'z'
  def pick_default = @picked = 'default'
end

Route.run(kind: 'c').picked     # => "bc"
Route.run(kind: 'zed').picked   # => "z"
Route.run(kind: 'x').picked     # => "default"
```

A branch's guard is checked after it's picked. A matched branch whose guard
opts out does nothing; it does **not** fall through to the next branch or the
`default`:

```ruby run
class Notify < Actionable::Action
  input  { required :kind, :string }
  output { optional :sent, :string }

  case_step :kind do
    on 'sms', :send_sms, if: :sms_enabled?
    default   :send_email
  end

  def kind         = input.kind
  def sms_enabled? = false
  def send_sms     = @sent = 'sms'
  def send_email   = @sent = 'email'
end

Notify.run(kind: 'sms').sent    # => nil
Notify.run(kind: 'push').sent   # => "email"
```

## Nested actions

`step ChildAction, input: [...], expose: [...]` runs another action as a step.

| Option | Default | Meaning |
|---|---|---|
| `input:` | none (the child gets no arguments) | names of parent instance variables passed to the child's `.run` as keywords: `input: %i[invoice]` calls `Child.run(invoice: @invoice)` |
| `expose:` | all | which of the child's output fields are copied back onto the parent as instance variables |

Only output fields the child actually set (an instance variable it assigned, or
a `succeed` / `skip` keyword) are copied, so a field it left `nil` or at its
default never overwrites the parent's value.

| Child outcome | Parent |
|---|---|
| success | absorbs the output and continues |
| skip | absorbs the output and continues, like a success; the child's skip never becomes the parent's outcome |
| failure | adopts the child's failure and halts |

```ruby run
class LookUp < Actionable::Action
  input  { required :sku, :string }
  output { optional :price, :integer }
  step :find
  def find = (input.sku == 'gone' ? fail!(:not_found, 'no such item') : @price = 25)
end

class Quote < Actionable::Action
  output { optional :price, :integer }

  def initialize(sku:)
    super()
    @sku = sku
  end

  step LookUp, input: %i[sku]
end

Quote.run(sku: 'abc').price      # => 25
Quote.run(sku: 'gone').code      # => :not_found
Quote.run(sku: 'gone').message   # => "no such item"
```

A child's failure crosses intact: its code, message, every error, its
`metadata` and its result class. It doesn't go through the parent's `fail`, so
an override of `fail` in a host base class never sees it. What the parent
declares for that code with [`fails`](../declared-outcomes/) fills in metadata
keys the child didn't set, and a parent that declares failures must declare the
codes its children can fail with.

## Checks before a run

Two checks run when `.run` is called, before any step:

- **Missing methods.** Every method a step or hook needs (method steps, case
  value sources, method branch targets) must be implemented by the action
  itself. Methods Ruby's core provides (`puts`, `exit`) don't count.
  Otherwise `.run` raises `Actionable::DefinitionError`:

```ruby run
class Unfinished < Actionable::Action
  step :missing
end

begin
  Unfinished.run
rescue Actionable::DefinitionError => e
  e.message   # => "Unfinished declares step(s) calling :missing but does not implement them"
end
```

- **Verb position.** On an action's first run, each step and hook method is
  parsed with Prism to check that a plain `fail` / `fail_with` / `skip` /
  `succeed` is the method's last expression. The rules are on the
  [control flow page](../control-flow/#where-a-plain-verb-may-go).

`@result` is reserved: a step that assigns it anything but a result raises
`DefinitionError` (`… set @result to a Integer; @result is reserved for the
run's result, so rename the instance variable`).

### Turning the verb-position check off

```ruby run
Actionable.verb_position_check?          # => true
Actionable.verb_position_check = false
Actionable.verb_position_check?          # => false
Actionable.verb_position_check = true
```

Off, `.run` never parses source or loads Prism, and the
[`Actionable/VerbNotLast` cop](../rubocop/) is the only guard. A class that ran
while the check was off is checked on its first run after it's back on.

Upstream: [USAGE, Steps](https://github.com/Paymentbox-com/actionable/blob/v1.9.0/USAGE.md#steps).
