---
title: Declared failures and result codes
description: Why an action can list the codes it fails or skips with, why the metadata on them is neutral, and why declaring one makes the action strict.
sidebar:
  order: 6
---

A result's `code` says how a run ended: `:success`, or a failure or skip code
the action chose. By default those codes are open-ended: any step can
`fail!(:anything)`. `fails` and `skips` let an action list them on the class
instead.

## The problem they solve

Decision D20 in the
[design record](https://github.com/Paymentbox-com/actionable/blob/v1.9.0/docs/origin/plan.md)
starts from a real case: "A failure's code was open-ended, so an adapter
couldn't know an action's failure contract." A host app wanted to attach its
own information to each code (whether it's a rejection, a not-found, and so
on) and had nowhere to put it except `fail`'s keywords, which already belong to
`errors`. An error on an attribute that happened to be called `kind` collided
with it.

The answer is to declare each code, with its default message and any metadata,
next to the steps:

```ruby run
class Charge < Actionable::Action
  fails :refused, 'the card was refused', kind: :rejected
  fails :not_found, kind: :not_found

  step :charge

  def charge = fail!(:refused, nil, kind: 'is not a known kind')
end

result = Charge.run
result.code           # => :refused
result.message        # => "the card was refused"
result.metadata       # => { kind: :rejected }
result.errors[:kind]  # => ["is not a known kind"]
```

`kind:` on the `fails` line is metadata; `kind:` on the `fail!` call is still
an error. The two no longer share a keyword space.

## Metadata is neutral

The gem never reads the metadata. D20: "the gem stores it, passes it through
and shows it, but never interprets it, so the gem stays unopinionated about
what a host means by a key such as `kind`." Your app decides what the keys
mean.

There's exactly one opt-in exception, and it's named: an action that calls
`honor_retry_metadata` (from `actionable/job`) lets the job adapter read a
`retry:` key. Without that call, `retry: true` is just data (D21, owner ruling
P10).

## Strict once declared

An action that declares any failure code may only fail with codes it declares.
Anything else raises `Actionable::DefinitionError` from the `fail` call itself:

```ruby run
class Refund < Actionable::Action
  fails :refused
  step :refund

  def refund = fail!(:timeout)
end

message = begin
  Refund.run
rescue Actionable::DefinitionError => e
  e.message
end
message.include?('fails with :timeout, which it does not declare')  # => true
```

Two things stay unchecked so existing code keeps working: an action that
declares nothing fails with any code, as before, and the codes the gem itself
emits are always allowed:

```ruby run
Actionable::Action::GEM_FAILURE_CODES  # => [:invalid_input, :invalid_output]
```

## Skips get the same contract

D21 extends this to skips with `skips`, for a reason worth quoting: "Declaring
skips too means every way an action can end is listed on the class." The rules
match `fails`, except that nothing is exempt, because the gem emits no skip
codes of its own. Even the default `:skipped` must be declared by an action that
declares skips. Declaring failures never makes skips strict, or the other way
round.

One difference is on purpose. A child action's *failure* becomes its parent's
failure, crossing "intact" (code, message, errors, metadata), so a declaring
parent must declare its children's failure codes. A child's *skip* doesn't
become the parent's outcome (see [Success, failure, skip](../three-outcomes/)),
so a parent doesn't declare its children's skip codes. D21 explains why that
stayed: propagating a child skip "would change what every existing composed
action returns."

## What a full list makes possible

Once every way an action can end is written on the class, tools can read it at
run time, with no source parsing:

- `describe` and `describe_text` show the declarations.
- `Actionable::RBS` emits `failure_code` and `skip_code` type aliases.
- The RSpec stubs refuse a code the action doesn't declare, since that would
  "test a failure the action can never return" (USAGE).
- Outcome coverage (D22, `actionable/rspec/coverage`) reports, at the end of a
  suite, each declared outcome no spec reached.
- Typed outcomes (D23, `typed_outcomes`) go one step further and give each
  code its own output schema.

## Related

- [Success, failure, skip](../three-outcomes/)
- [USAGE: Declared failures](https://github.com/Paymentbox-com/actionable/blob/v1.9.0/USAGE.md#declared-failures)
  and [Declared skips](https://github.com/Paymentbox-com/actionable/blob/v1.9.0/USAGE.md#declared-skips)
