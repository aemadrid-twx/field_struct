---
title: Validation and errors
description: The setter pipeline, every error message FieldStruct writes, the coercion failure policy, cross-field validation and the Errors API.
sidebar:
  order: 4
---

Construction and validity are separate: `new` builds an object even from bad
input, and `valid?` tells you whether to trust it.

## The setter pipeline

Every assignment, whether through `new`, `assign_attributes`, `with` or
`record.field = value`, runs the same steps for that one field:

1. **Immutable check.** After construction, an `immutable!` class raises
   `FieldStruct::ImmutableError`.
2. **Coerce** through the field's type. If coercion raises `ArgumentError`,
   `TypeError` or `RangeError`, the [coercion policy](#coercion-failure-policy)
   takes over and the steps below don't run.
3. **Store** the coerced value.
4. **Clear** this field's errors.
5. **Missing?** If the type says the value is missing, a required field gets
   `"is required"`. Either way, checking stops here.
6. **Invalid?** A `format:` Regexp mismatch, an `enum:` or `in:` miss, an
   invalid nested struct, or an array holding an invalid struct adds
   `"is invalid"` (once, however many checks failed). Otherwise, array elements
   breaking their `element:` checks add `"element at index 1 is invalid"` /
   `"elements at index 0, 2 are invalid"`.

The setter owns its field's errors: each assignment rewrites them, so fixing a
field clears its error. `valid?` reads `errors.empty?` after rerunning the
cross-field validators; it never recoerces fields.

```ruby run
class Book < FieldStruct::Base
  required :title, :string
  required :price, :decimal, in: (0..)
end

book = Book.new(title: ' ', price: '-5')
book.valid?       # => false
book.errors.to_h  # => { title: ["is required"], price: ["is invalid"] }

book.title = 'Eloquent Ruby'
book.price = '24.99'
book.valid?       # => true
```

"Required" means present **and** valid. A required reader can still return
`nil` or a raw value on an invalid object, so check `valid?` first.

## Messages

| Message | When |
|---|---|
| `is required` | a required field's value is missing after coercion |
| `is invalid` | `format:` / `enum:` / `in:` failed, or a nested struct (or a struct in an array) is invalid |
| `element at index N is invalid` / `elements at index …  are invalid` | array elements failed their `element:` checks |
| `could not be coerced: <reason>` | coercion failed under `:keep_raw` or `:replace` |

What "missing" means is up to the type: nil, empty or whitespace-only for
`:string` and its subtypes; nil or empty for `:array` and `:binary`; nil for
everything else. `0` and `false` are present.

Coercion reasons name the type and the input's **class**, never the value, so
they're safe to log:

```ruby run
class Order < FieldStruct::Base
  optional :qty,  :integer
  optional :paid, :boolean
end

Order.new(qty: 'lots').errors[:qty]   # => ["could not be coerced: Integer fields expect a base-10 integer, got a String that is not one"]
Order.new(paid: 'maybe').errors[:paid] # => ["could not be coerced: Boolean fields expect true, false, 1, 0 or one of the strings \"true\", \"1\", \"false\", \"0\", got a String that is not one"]
```

Raised errors follow the same rule: a `CoercionError`, a type's
`ArgumentError` / `TypeError`, and `from_json`'s parse error never quote the
input, and the Kernel conversion errors that would (`invalid value for
Integer(): "…"`) are dropped from the `cause` chain.

## Coercion failure policy

What happens when a value can't be coerced. Set it per class with
`coercion_policy` (see [Class macros](../class-macros/)) or per field with
`coercion_policy:`. A field's setting wins over its class's.

| Policy | Stored value | Error | Notes |
|---|---|---|---|
| `:keep_raw` (default) | the raw input | `could not be coerced: …` | nothing is lost |
| `:replace` | `nil` | `could not be coerced: …` | |
| `:raise` | unchanged | none | raises `FieldStruct::CoercionError` |

A failed coercion records only the coercion error: a required field holding
`nil` under `:replace` doesn't also get `"is required"`.

```ruby run
class Mixed < FieldStruct::Base
  coercion_policy :replace
  required :count,  :integer
  optional :strict, :integer, coercion_policy: :raise
  optional :raw,    :integer, coercion_policy: :keep_raw
end

m = Mixed.new(count: 'x', raw: 'y')
m.count       # => nil
m.raw         # => "y"
m.errors.to_h.keys # => [:count, :raw]

err = begin
  Mixed.new(count: 1, strict: 'z')
rescue FieldStruct::CoercionError => e
  e
end
err.message     # => "could not coerce String input for strict: Integer fields expect a base-10 integer, got a String that is not one"
err.field_name  # => :strict
err.original.class # => ArgumentError
```

## Cross-field validation

`validate` registers checks that look at more than one field. Pass method names,
a block (which receives the record), or both; each call appends, and they run in
declaration order.

```ruby run
class Schedule < FieldStruct::Base
  required :start_date, :date
  required :end_date,   :date

  validate :ensure_chronological
  validate do |record|
    record.errors.add(:base, 'must span at least one day') if record.end_date == record.start_date
  end

  def ensure_chronological
    return unless start_date && end_date

    errors.add(:base, 'end_date must not precede start_date') if start_date > end_date
  end
end

bad = Schedule.new(start_date: '2024-02-01', end_date: '2024-01-15')
bad.errors[:base] # => ["end_date must not precede start_date"]
bad.valid?        # => false

bad.end_date = '2024-02-01'
bad.valid?        # => false
bad.errors[:base] # => ["must span at least one day"]
```

- Validators run at the end of `new` (so a fresh object already has its
  `:base` errors), on every `valid?` / `invalid?`, and in `with`.
- `errors[:base]` is cleared before each run, so stale entries don't pile up.
- Errors a validator writes to a **field** are not cleared by the next run.
  Use `:base`, or manage those entries yourself.
- A class with no validators skips this step, and `valid?` is just
  `errors.empty?`.
- Validators are inherited: a subclass starts with a copy of its parent's list
  and can add more. There's no way to remove an inherited one.

```ruby run
class Tagged < FieldStruct::Base
  required :year, :integer
  validate { |r| r.errors.add(:year, 'is too old') if r.year && r.year < 2000 }
end

t = Tagged.new(year: 1999)
t.valid?
t.errors[:year] # => ["is too old", "is too old"]
```

## Validity is computed on assignment

A parent records an invalid nested struct (or array element) when that value is
**assigned**. It doesn't watch it afterwards. Changing a nested struct or an
array in place leaves the parent's errors as they were, in both directions.

```ruby run
class Address < FieldStruct::Base
  required :city, :string
end

class Person < FieldStruct::Base
  required :address, Address
  optional :tags,    :array, of: :string
end

person = Person.new(address: { city: 'Provo' })
person.address.city = nil         # broken in place
person.address.valid?             # => false
person.valid?                     # => true

person.address = person.address   # reassign: the setter revalidates
person.valid?                     # => false
person.errors[:address]           # => ["is invalid"]

person.address.city = 'Provo'     # fixed in place
person.valid?                     # => false
person.with(address: person.address).valid? # => true

person.tags = ['a']
person.tags << 5                  # in-place push: no coercion
person.tags                       # => ["a", 5]
person.tags = person.tags         # reassign coerces each element
person.tags                       # => ["a", "5"]
```

To revalidate, assign the field again, or go through `assign_attributes` or
`with`. For a nested struct you change often, make it `immutable!` and use
`with`, so every change goes through a setter.

## The `Errors` object

`record.errors` is a `FieldStruct::Errors`. Field names may be Symbols or
Strings.

| Method | Returns |
|---|---|
| `errors[:field]` | Array of messages, `[]` when none |
| `errors.add(:field, 'msg')` | appends a message |
| `errors.clear(:field)` | removes a field's messages, returns `nil` |
| `errors.empty?` | `true` when no field has a message |
| `errors.to_h` / `errors.messages` | `{field => [messages]}`, empty fields left out |
| `errors.full_messages` | each message as a sentence: humanized field name prepended; `:base` messages unchanged |
| `errors.inspect` | `#<FieldStruct::Errors title=["is required"]>`, or `#<FieldStruct::Errors empty>` |

```ruby run
errors = FieldStruct::Errors.new
errors.add(:first_name, 'is required')
errors.add(:base, 'Something else is wrong')

errors['first_name']     # => ["is required"]
errors[:nope]            # => []
errors.full_messages     # => ["First name is required", "Something else is wrong"]
errors.clear(:first_name)
errors.to_h              # => { base: ["Something else is wrong"] }
errors.empty?            # => false
```

`dup` / `clone` of a record copy its errors: the copy starts with the same
messages but owns them.

Upstream: [USAGE, Validation semantics](https://github.com/Paymentbox-com/field_struct/blob/v0.16.0/USAGE.md#validation-semantics-important).
