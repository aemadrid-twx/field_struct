---
title: Class macros
description: coercion_policy, unknown_attributes, immutable!, frozen!, validate and serialize — what each does and how it inherits.
sidebar:
  order: 5
---

Class-level settings, declared in the class body. All of them are inherited by
subclasses.

| Macro | Values | Default | Reader |
|---|---|---|---|
| `coercion_policy` | `:keep_raw`, `:replace`, `:raise` | `:keep_raw` | `coercion_policy` (no argument) |
| `unknown_attributes` | `:ignore`, `:raise` | `:ignore` | `unknown_attributes` (no argument) |
| `immutable!` | — | mutable | `immutable?` |
| `frozen!` | — | not frozen | `frozen_on_construct?` |
| `validate` | method names and/or a block | none | `validators` |
| `serialize` | format name + `field: 'external'` pairs | none | `metadata.serializations` |

`validate` is covered in [Validation and errors](../validation-and-errors/#cross-field-validation)
and `serialize` in [JSON and serialization](../json-and-serialization/).

## `coercion_policy`

What the setter does when a value can't be coerced. See
[Coercion failure policy](../validation-and-errors/#coercion-failure-policy) for
the full table. A field's own `coercion_policy:` option wins over the class's.

```ruby run
class Strict < FieldStruct::Base
  coercion_policy :raise
  required :age, :integer
end

Strict.coercion_policy # => :raise

err = begin
  Strict.new(age: 'abc')
rescue FieldStruct::CoercionError => e
  e
end
err.message # => "could not coerce String input for age: Integer fields expect a base-10 integer, got a String that is not one"
```

An unknown value raises `ArgumentError`: `unknown coercion policy :nope
(expected one of [:keep_raw, :replace, :raise])`.

## `unknown_attributes`

What `new`, `assign_attributes`, `with` and `from_json` do with input keys that
don't match a declared field. `:ignore` drops them silently; `:raise` raises
`FieldStruct::UnknownAttributeError`, whose `keys` names the extras (names only,
never values). String keys are compared as Symbols.

```ruby run
class Card < FieldStruct::Base
  unknown_attributes :raise
  required :last4, :string
end

class Charge < FieldStruct::Base
  unknown_attributes :raise
  required :amount, :decimal
  required :card,   Card
  serialize :json, amount: 'amountDecimal'
end

Charge.from_json('{"amountDecimal":"9.99","card":{"last4":"4242"}}').valid? # => true

typo = begin
  Charge.from_json('{"ammount":"9.99","card":{"last4":"4242"}}')
rescue FieldStruct::UnknownAttributeError => e
  e
end
typo.keys    # => [:ammount]
typo.message # => "unknown attribute(s) for Charge: :ammount"

nested = begin
  Charge.new(amount: 1, card: { last4: '4242', cvv: '123' })
rescue FieldStruct::UnknownAttributeError => e
  e
end
nested.message # => "unknown attribute(s) for Card: :cvv"
```

- Declare it on **every** struct that reads input. It's inherited by
  subclasses, not by the structs a field nests: a nested class without it still
  drops its own unknown keys.
- An error raised inside a nested struct's `new` propagates out of the parent,
  whatever the parent's `coercion_policy`.
- `from_json` reverse-maps `serialize :json` names first, so external names are
  known keys there. `new` takes canonical names only, so `amountDecimal:` passed
  to `Charge.new` raises.

## `immutable!`

After `new` finishes, every setter raises `FieldStruct::ImmutableError`.
Defaults, `new` and `with` still work, because they assign before (or, for
`with`, on a fresh copy before) the object is marked initialized.

```ruby run
class Config < FieldStruct::Base
  immutable!
  required :api_key, :string
end

c = Config.new(api_key: 'sk-1')
Config.immutable? # => true

err = begin
  c.api_key = 'sk-2'
rescue FieldStruct::ImmutableError => e
  e
end
err.message # => "Config is immutable; cannot reassign api_key"

c.with(api_key: 'sk-2').api_key # => "sk-2"
```

## `frozen!`

The instance is Ruby-frozen at the end of `new`, so any setter (or other
instance-variable write) raises Ruby's `FrozenError`. `valid?`, `as_json`,
`to_json` and `to_h` still work. `with` returns a frozen copy.

```ruby run
class FrozenConfig < FieldStruct::Base
  frozen!
  required :api_key, :string
end

fc = FrozenConfig.new(api_key: 'sk-1')
fc.frozen?                          # => true
FrozenConfig.frozen_on_construct?   # => true
fc.with(api_key: 'sk-2').frozen?    # => true

err = begin
  fc.api_key = 'x'
rescue FrozenError => e
  e
end
err.class # => FrozenError
```

`immutable!` and `frozen!` are independent and can be stacked. When both apply,
`immutable!`'s check runs first, so a setter raises `ImmutableError`.

| Macro | Mechanism | A setter after `new` raises |
|---|---|---|
| `immutable!` | FieldStruct's own check in the setters | `FieldStruct::ImmutableError` |
| `frozen!` | `Object#freeze` at the end of `new` | `FrozenError` |

## Inheritance

Every macro is inherited. A subclass overrides by declaring it again, and the
override never changes the parent. `immutable!` and `frozen!` are one-way: there
is no `mutable!` or `unfrozen!`.

```ruby run
class Base1 < FieldStruct::Base
  coercion_policy :raise
  unknown_attributes :raise
  immutable!
end

class Guest < Base1
  coercion_policy :keep_raw
end

Guest.coercion_policy     # => :keep_raw
Base1.coercion_policy     # => :raise
Guest.unknown_attributes  # => :raise
Guest.immutable?          # => true
```

| Macro | Inherited | Override on a subclass |
|---|---|---|
| `coercion_policy` | yes | any value |
| `unknown_attributes` | yes | `:ignore` or `:raise` |
| `immutable!` | yes | can add, not remove |
| `frozen!` | yes | can add, not remove |
| `validate` | yes (a copy of the parent's list) | can add, not remove |
| `serialize` | yes | redeclaring a format replaces it |
| fields | yes | redeclaring a field replaces it |

Because `immutable!` and `frozen!` can't be undone, put them on the leaf classes
that need them rather than on a shared parent.

Upstream: [USAGE, Class macros](https://github.com/aemadrid-twx/field_struct/blob/v0.16.0/USAGE.md#class-macros).
