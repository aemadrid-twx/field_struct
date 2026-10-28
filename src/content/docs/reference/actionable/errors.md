---
title: Errors and guardrails
description: "The exception classes actionable raises and every check that raises them."
sidebar:
  order: 13
---

## Exception classes

| Class | Superclass | Raised for |
|---|---|---|
| `Actionable::Error` | `StandardError` | base class |
| `Actionable::DefinitionError` | `Actionable::Error` | a misconfigured action (below) |
| `Actionable::Job::RetryableFailure` | `StandardError` | `run_actionable` on a `:retry` disposition ([jobs](../jobs/)); `#result` holds the result |
| `Actionable::Coverage::BaselineMismatch` | `Actionable::Error` | the coverage report disagrees with its baseline ([testing](../testing/#the-report-and-the-baseline)) |

```ruby run
Actionable::DefinitionError.ancestors.take(3)   # => [Actionable::DefinitionError, Actionable::Error, StandardError]
```

A halt (`fail!`, `succeed!`, `skip!`, `halt!`) is `throw :actionable_halt`, not
an exception, and the runner never rescues exceptions: anything a step raises
reaches the caller of `.run`.

## Every check

| When | Check | Raises |
|---|---|---|
| declaring `output` (or a `fails` / `skips` block) | a field in the [reserved names](../input-and-output/#reserved-output-names) | `DefinitionError` |
| declaring `step` / `case_step` branch | a target that is not a Symbol, String or action class | `ArgumentError` |
| `measure` | unknown mode, or `:sampled` without a `rate:` between 0 and 1 | `ArgumentError` |
| `typed_outcomes` | the action already has its own `Success` / `Failure` / `Skipped` constant | `DefinitionError` |
| start of `.run` | a step or hook method that is not implemented | `DefinitionError` |
| first `.run` of a class | a plain verb with code after it ([rules](../control-flow/#where-a-plain-verb-may-go)) | `DefinitionError` |
| a `fail` / `skip` call | a code that is not an identifier | `ArgumentError` |
| a `fail` / `fail_with` call | an undeclared code, once the action declares failures | `DefinitionError` |
| a `skip` call | an undeclared code, once the action declares skips | `DefinitionError` |
| a `fail` / `skip` call under typed outcomes | output for a code without a schema | `DefinitionError` |
| same | `output:` that is not a Hash or a FieldStruct | `ArgumentError` |
| `fail_with(…, output:)` | without typed outcomes | `ArgumentError` |
| after the steps (after each step when measuring) | `@result` set to something other than a result | `DefinitionError` |
| declaring `after_commit` (Rails adapter) | ActiveRecord missing or older than 7.2 | `DefinitionError` |

```ruby run
class Typo < Actionable::Action
  step :chrage
  def charge = nil
end

begin
  Typo.run
rescue Actionable::DefinitionError => e
  e.message   # => "Typo declares step(s) calling :chrage but does not implement them"
end

class Clobber < Actionable::Action
  step :go
  def go = @result = 'done'
end

begin
  Clobber.run
rescue Actionable::DefinitionError => e
  e.message   # => "Clobber set @result to a String; @result is reserved for the run's result, so rename the instance variable"
end

begin
  Class.new(Actionable::Action) { measure :sometimes }
rescue ArgumentError => e
  e.message   # => "unknown measure mode :sometimes"
end
```

Upstream: [USAGE, Guardrails](https://github.com/aemadrid-twx/actionable/blob/v1.10.0/USAGE.md#guardrails-definitionerror).
