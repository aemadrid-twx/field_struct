---
title: Coercion vs. validation
description: FieldStruct first turns input into the field's type, then judges the typed value. Two steps, two kinds of error, and a policy for when the first one fails.
sidebar:
  order: 3
---

Every assignment does two different jobs. **Coercion** asks "can this input
become the field's type?" **Validation** asks "now that it has, is the value
acceptable?" FieldStruct keeps them apart, and each has its own error message.

```ruby run
class Order < FieldStruct::Base
  required :quantity, :integer, in: 1..10
end

Order.new(quantity: '3').quantity          # => 3
Order.new(quantity: 'lots').errors.to_h    # => { quantity: ["could not be coerced: Integer fields expect a base-10 integer, got a String that is not one"] }
Order.new(quantity: '50').errors.to_h      # => { quantity: ["is invalid"] }
Order.new.errors.to_h                      # => { quantity: ["is required"] }
```

- `'lots'` never became an Integer: a coercion failure.
- `'50'` became `50` fine, but `50` is outside `in: 1..10`: a validation
  failure, `"is invalid"`.
- A missing value is a validation failure too, `"is required"`.

## Validation judges the coerced value

`in:`, `enum:` and `format:` run *after* coercion, so `'10'` is compared as
`10` (README, "Restricting values"). The same goes for presence. The design
record defines required as "value is not missing after coercion" (D4), and the
*type* decides what missing means:

| Type | Missing when |
|---|---|
| `:string` and its subtypes | `nil`, empty, or whitespace-only |
| numbers, `:boolean`, dates and times | `nil` only, so `0` and `false` are present |
| `:array` | `nil` or empty |

```ruby run
class Flags < FieldStruct::Base
  required :count,   :integer
  required :enabled, :boolean
  required :label,   :string
end

Flags.new(count: 0, enabled: false, label: '  ').errors.to_h  # => { label: ["is required"] }
```

D4 adds: "Defaults satisfy required (the *value* is what's checked, not
whether the input hash contained the key)."

Where a type can catch bad input either way, the design picks validation. The
`:uuid`, `:url` and `:email` types are strings with a default `format:`, "so
bad input becomes a `'is invalid'` validation error (not a coercion error)"
(design record, "Extended scalar types").

## When coercion fails: the policy

A coercion failure has to leave *something* in the field. The class (or the
field) chooses what, with `coercion_policy` (decision D3):

| Policy | The field holds | Error recorded |
|---|---|---|
| `:keep_raw` (default) | the raw input | yes |
| `:replace` | `nil` | yes |
| `:raise` | nothing: the setter raises `FieldStruct::CoercionError` | — |

```ruby run
class Lenient < FieldStruct::Base
  optional :age, :integer
end

class Cleared < FieldStruct::Base
  coercion_policy :replace
  optional :age, :integer
end

Lenient.new(age: 'lots').age   # => "lots"
Cleared.new(age: 'lots').age   # => nil
```

The written reasons are short. USAGE describes `:keep_raw` as "nothing lost;
inspect & fix". D3 says `:replace` always stores `nil` rather than a type's
"empty" value "to keep the surface small". The policy started as class-only;
a per-field override (`coercion_policy:` on the field) was added later.

Under `:keep_raw` and `:replace` the object is simply invalid, which fits
[validity computed on assignment](../validity-on-assignment/): you build it,
then ask `valid?`.

## Lenient by default, strict on request

The default coercions are forgiving. `:string` calls `to_s` on almost
anything, and `:integer` truncates `12.7` to `12`. USAGE gives the reason: "The
defaults are lenient on purpose: they match what ActiveModel does, so a Rails
client sees the same values." A field that mustn't accept "close enough" opts
in with `strict: true`, which only ever *narrows* what's accepted:

```ruby run
class Charge < FieldStruct::Base
  optional :loose_cents,  :integer
  optional :strict_cents, :integer, strict: true
end

charge = Charge.new(loose_cents: 12.7, strict_cents: 12.7)
charge.loose_cents   # => 12
charge.strict_cents  # => 12.7
charge.errors[:strict_cents].first.start_with?('could not be coerced')  # => true
```

Some inputs are refused even by default, because accepting them would mean
guessing. For dates and times, USAGE says the rules "exist because the stdlib
parsers answer questions they were not asked": `Time.parse('10:30')` means
*today* at 10:30, so a value whose meaning depends on when it was parsed is
refused, and so is a day that never existed, like 31 June.

## Messages never echo the input

Look again at the coercion message above: it names the type and the input's
*class* ("got a String"), not the value. That's deliberate. USAGE: "Payments
data must not reach a log line, so **no message FieldStruct builds echoes an
input value**." It applies to `errors` entries, raised errors and their
`cause` chain.

## Related

- [Validity is computed on assignment](../validity-on-assignment/)
- [USAGE: Coercion failure policy](https://github.com/aemadrid-twx/field_struct/blob/v0.16.0/USAGE.md#coercion-failure-policy)
  and [Strict coercion](https://github.com/aemadrid-twx/field_struct/blob/v0.16.0/USAGE.md#strict-coercion-strict-true)
