---
title: Validity is computed on assignment
description: Why every FieldStruct setter validates its own field, why valid? is a cheap read, and why an invalid object never looks fine.
sidebar:
  order: 2
---

A FieldStruct doesn't wait for you to ask whether it's valid. Every time a
field is assigned, that field is checked, and the result is kept in `errors`.
`valid?` just reads what's already there.

## What a setter does

Each setter runs the same pipeline: coerce the value, store it, check presence,
check `format:` / `enum:` / `in:`, and rewrite that field's entry in `errors`
(decision D5 in the
[design record](https://github.com/Paymentbox-com/field_struct/blob/v0.15.0/docs/origin/plan.md)).
The setter *owns* its field's errors: it clears them and writes them again on
every assignment, whatever was there before.

```ruby run
class User < FieldStruct::Base
  required :name, :string
  optional :age,  :integer
end

user = User.new(name: 'Alice', age: '30')
user.valid?          # => true

user.name = ''
user.errors[:name]   # => ["is required"]
user.valid?          # => false

user.name = 'Alicia'
user.errors[:name]   # => []
user.valid?          # => true
```

`new` and `assign_attributes` aren't a separate path. They call the same
setters, one field at a time. So an object built from a Hash and an object
built up field by field end in exactly the same state.

## Why it works this way

The design records give two reasons.

- **Coercion must hold after construction, not only during it.** The very
  first design notes say so: "Setters must coerce after initialization, not
  only at construction time" ([first discussion](https://github.com/Paymentbox-com/field_struct/blob/v0.15.0/docs/origin/first_discussion.md)).
- **There's nothing left to compute later.** D5: "`valid?` is a cheap read of
  `errors.empty?`, no recomputation. Lazy/eager distinction doesn't apply
  because validation is already a side effect of mutation."

The one exception is cross-field validation. A `validate` block looks at
several fields at once, so no single setter can own it. Those blocks run at the
end of `new` and again on every `valid?` call, and they write to
`errors[:base]`, which is cleared before each run (decision V2/V3).

The cost is paid per assignment: the README's benchmark notes that "the cost
scales with the number of fields assigned rather than with the size of the
class."

## Building is not validating

Because validation happens as data arrives, bad data doesn't stop `new`. You
get an object back, and it tells you what's wrong. The design record keeps the
two apart on purpose: the
[USAGE mental model](https://github.com/Paymentbox-com/field_struct/blob/v0.15.0/USAGE.md)
says "Construction and validity are *separate*: you can build an invalid
instance; ask `valid?`."

That has one consequence you must remember: a required field can still hold
`nil`, or the raw input when coercion failed. Gate on `valid?`, never on
"it was declared required".

```ruby run
broken = User.new(age: 'lots')
broken.name      # => nil
broken.age       # => "lots"
broken.valid?    # => false
```

## An invalid object never looks fine

`inspect` shows the errors too. A valid object reads cleanly; an
invalid one appends what's wrong:

```ruby run
User.new(name: 'Alice', age: 30).inspect  # => '#<User name: "Alice", age: 30>'
User.new(name: '', age: 30).inspect       # => '#<User name: "", age: 30 errors: {name: ["is required"]}>'
```

This is one of field_struct's design invariants: "The public surface explains
itself without source. Errors render as full sentences; `inspect` shows state
*and* validity"
([project intent](https://github.com/Paymentbox-com/field_struct/blob/v0.15.0/.claude/project_intent.md)).
It serves the gem's stated primary goal, legibility for both human and AI
readers. `inspect` only reads `errors`; printing an object never re-runs
validation or changes it.

## The trade-off: nested values go stale

A parent checks a nested struct, or an array's elements, when the field is
*assigned*. It doesn't watch them afterwards (decision N3: "Nested mutations
after assignment do **not** refresh the parent's view"). Change a nested struct
in place and the parent's errors don't move:

```ruby run
class Address < FieldStruct::Base
  required :city, :string
end

class Person < FieldStruct::Base
  required :address, Address
end

person = Person.new(address: { city: 'Provo' })
person.address.city = nil
person.address.valid?   # => false
person.valid?           # => true

person.address = person.address
person.valid?           # => false
```

That's the price of "the setter owns its field's errors": only a setter
changes them. The fix is to go through a setter again, either by re-assigning
the field or with `with` / `assign_attributes`. For a nested struct you change
often, USAGE suggests making it `immutable!` and changing it with `with`, so
the only way to change it is through a setter.

## Related

- [Coercion vs. validation](../coercion-and-validation/): what the pipeline's
  two halves each check.
- [USAGE: Validity is computed on assignment](https://github.com/Paymentbox-com/field_struct/blob/v0.15.0/USAGE.md#validity-is-computed-on-assignment-shallow-valid-staleness)
