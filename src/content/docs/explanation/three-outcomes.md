---
title: Success, failure, skip
description: Why an action run ends in one of three outcomes, why a skip is neither a success nor a failure, and why halting uses throw instead of exceptions.
sidebar:
  order: 5
---

Every actionable run returns one result, and it is always one of three kinds:
`Success`, `Failure` or `Skipped`. The first two are obvious. This page is
mostly about the third one, and about how a step stops the run.

## Why a skip is its own outcome

Sometimes an action has nothing to do: the record it would update doesn't
exist yet, or the work was already done. Decision D17 in the
[design record](https://github.com/aemadrid-twx/actionable/blob/v1.10.0/docs/origin/plan.md)
puts it like this: a skip "is *not* a failure (no error, no retry/alert) and
*not* a success (no real work), so conflating it with either loses information
for observability, retries, and composition."

So a skip is a strict third state, and `success?` and `failure?` are both
false:

```ruby run
class SyncField < Actionable::Action
  step :sync

  def sync = skip!(:not_ready, 'the field is not created yet')
end

result = SyncField.run
result.class      # => Actionable::Skipped
result.skipped?   # => true
result.success?   # => false
result.failure?   # => false
result.ok?        # => true
result.code       # => :not_ready
```

`ok?` (that is, `!failure?`) is there for the common question "did anything go
wrong?". A success and a skip answer it the same way.

Each place that consumes a result handles a skip on purpose, as D17 lists:

| Where | What a skip does |
|---|---|
| Lifecycle hooks | runs `on_skip`, never `on_success` or `on_failure`, then `always` |
| Output | captured best-effort and never validated, like a failure |
| Nested action | the parent continues as if the child succeeded, and decides its own outcome |
| Transaction (Rails adapter) | commits: a skip is not a failure, so nothing rolls back |
| Job adapter | `:ack`, not a retry |

The nested case is easy to check:

```ruby run
class Parent < Actionable::Action
  output { optional :finished, :boolean }

  step SyncField
  step :finish

  def finish = @finished = true
end

Parent.run.success?   # => true
Parent.run.finished   # => true
```

## Recording an outcome isn't stopping

Each outcome has two verbs. `fail`, `succeed` and `skip` *record* a result and
let the steps keep running. `fail!`, `succeed!` and `skip!` record it and stop.
The last recorded result wins:

```ruby run
class LastWins < Actionable::Action
  step :check
  step :recover

  def check   = fail(:declined)
  def recover = succeed('retried with another card')
end

LastWins.run.success?   # => true
```

D4 records that this split "deliberately fixes the old gem's inconsistency
where a plain `fail` silently short-circuited because it set the `finished?`
flag." But a plain `fail` followed by more code is an easy mistake to make. So
on an action's first run the gem checks that each plain verb is its method's
last expression, and raises a `DefinitionError` otherwise (USAGE, "Where a plain verb
may go").

## Halting with throw, not exceptions

The bang verbs stop the pipeline with `throw :actionable_halt`, which the
runner catches. They don't raise. And the runner never rescues your
exceptions, so a real error reaches you untouched:

```ruby run
class Broken < Actionable::Action
  step :work

  def work = raise(ArgumentError, 'a real bug')
end

error = begin
  Broken.run
rescue ArgumentError => e
  e
end
error.message   # => "a real bug"
```

This was one of the reasons we rebuilt the gem. The original
"short-circuited via exceptions caught by a bare `rescue Exception` in the
runner, which also swallowed genuine errors and resisted typing"
([first discussion](https://github.com/aemadrid-twx/actionable/blob/v1.10.0/docs/origin/first_discussion.md)).
It is now design invariant 2: "Control flow is `throw`/`catch`, never
exceptions."

So a `Failure` always means the action _decided_ to fail. A crash is an
exception, and it stays one.

## Related

- [Declared failures and result codes](../declared-outcomes/): listing every
  code an action can end with.
- [USAGE: Control flow](https://github.com/aemadrid-twx/actionable/blob/v1.10.0/USAGE.md#control-flow)
