---
title: Hooks and history
description: "Lifecycle hooks (on_success, on_failure, on_skip, always), how halts behave in them, measure modes and the History API."
sidebar:
  order: 6
---

## Lifecycle hooks

Hooks run after the main steps, chosen by the outcome the steps produced.

| Macro | Runs when |
|---|---|
| `on_success target, **options` | the result is a `Success` |
| `on_failure target, **options` | the result is a `Failure` |
| `on_skip target, **options` | the result is a `Skipped` |
| `always target, **options` | every run, after the outcome hooks |

A target is a method name or an action class, like a step, and takes `if:` /
`unless:`. Hooks are inherited, and redeclaring one replaces it in place
([redeclaration](../actions-and-steps/#redeclaring-a-step)). `success_hooks`,
`failure_hooks`, `skip_hooks` and `always_hooks` return each list.

The outcome is chosen once, after the main steps, and isn't re-dispatched. Hooks
may use the [verbs](../control-flow/). A bang verb in a hook records its result
and stops the remaining hooks of its phase; `halt!` stops them and keeps the
current result. A nested action used as a hook that fails counts as a `fail!`.

| A halt in… | Still runs | Final result |
|---|---|---|
| an outcome hook (`on_success` / `on_failure` / `on_skip`) | every `always` hook, not the rest of that outcome's hooks | the halting hook's |
| an `always` hook | nothing; the rest of the `always` hooks are skipped | the halting hook's |

```ruby run
class Verified < Actionable::Action
  step :work
  on_success :verify
  on_success :announce
  always :audit

  def work     = nil
  def verify   = fail!(:verification_failed)
  def announce = $announced = true
  def audit    = $audited = result.code
end

Verified.run.code   # => :verification_failed
$announced          # => nil
$audited            # => :verification_failed
```

Output is captured and validated again after each hook, and `succeed` / `skip`
keywords keep winning over instance variables. With the Rails adapter, hooks run
inside the `transactional` transaction, and there's an extra
[`after_commit`](../rails/#after_commit) hook.

## Measurement

`measure` sets whether a run records a [`History`](#history):

| Call | Records |
|---|---|
| `measure :none` (default) | nothing |
| `measure :all` | every run |
| `measure :sampled, rate: 0.1` | a run with probability `rate` (a Numeric between 0 and 1, required) |
| `measure` | reads the mode |

An unknown mode, or `:sampled` without a valid `rate:`, raises `ArgumentError`
(`measure :sampled requires rate: between 0 and 1, got nil`). `measure_rate`,
`measure_all?` and `measure_sampled?` read the setting; the mode is inherited.

A measured run also measures every nested action it runs, whatever their own
setting. Measurement state is fiber-local, so a nested action run inside
another Fiber (including `Enumerator#next`) isn't recorded in the parent's
history.

## History

`result.history` is an `Actionable::History` when the run was measured, and `[]`
otherwise. It records each step and hook that ran (a guarded-off step isn't
recorded).

| `History` | |
|---|---|
| `steps` | Array of `History::Step` |
| `took` | sum of the step durations, in seconds |
| `empty?` | no steps recorded |
| `as_json` / `to_json` | Array of step hashes; JSON through Oj |

| `History::Step` | |
|---|---|
| `section` | `:main`, `:success`, `:failure`, `:skip` or `:always` |
| `name` | the method name, or the nested action's class |
| `started_at` | wall-clock `Time` |
| `duration` | seconds, from the monotonic clock |
| `code` | the result code the step recorded, or `nil` if it recorded none |
| `nested` | the nested action's `History`, for an action step |

```ruby run
class Timed < Actionable::Action
  measure :all
  step :work
  on_success :done
  def work = nil
  def done = succeed('finished')
end

history = Timed.run.history
history.steps.map { |s| [s.section, s.name, s.code] }   # => [[:main, :work, nil], [:success, :done, :success]]
history.took.is_a?(Float)                               # => true
history.as_json.first.keys                              # => [:section, :name, :started_at, :duration, :code, :history]

class Untimed < Actionable::Action
  step :work
  def work = nil
end

Untimed.run.history   # => []
```

```ruby run
class Sampled < Actionable::Action
  measure :sampled, rate: 1.0
  step :work
  def work = nil
end

Sampled.measure                        # => :sampled
Sampled.measure_rate                   # => 1.0
Sampled.run.history.steps.map(&:name)  # => [:work]
```

Upstream: [USAGE, Lifecycle hooks](https://github.com/Paymentbox-com/actionable/blob/v1.9.0/USAGE.md#lifecycle-hooks) and [History & measurement](https://github.com/Paymentbox-com/actionable/blob/v1.9.0/USAGE.md#history--measurement).
