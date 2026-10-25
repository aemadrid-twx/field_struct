---
title: Exceptions
description: Every exception FieldStruct raises, what raises it, and what it carries.
sidebar:
  order: 10
---

FieldStruct's own exceptions share a base class:

```text
StandardError
└── FieldStruct::Error
    ├── FieldStruct::CoercionError        (field_name, original)
    ├── FieldStruct::ImmutableError
    └── FieldStruct::UnknownAttributeError (keys)
```

```ruby run
FieldStruct::Error.superclass                 # => StandardError
FieldStruct::CoercionError.superclass         # => FieldStruct::Error
FieldStruct::ImmutableError.superclass        # => FieldStruct::Error
FieldStruct::UnknownAttributeError.superclass # => FieldStruct::Error
```

| Exception | Raised by | Carries |
|---|---|---|
| `FieldStruct::CoercionError` | a setter, when coercion fails under `coercion_policy :raise` (class or field) | `field_name` (Symbol), `original` (the type's `ArgumentError` / `TypeError` / `RangeError`) |
| `FieldStruct::ImmutableError` | a setter called after `new` on an `immutable!` class | — |
| `FieldStruct::UnknownAttributeError` | `new`, `assign_attributes`, `with`, `from_json`, under `unknown_attributes :raise` | `keys` (Array of Symbols) |
| `FrozenError` (Ruby's) | a setter on a `frozen!` instance | — |
| `ArgumentError` | a bad declaration (see [Fields and options](../fields-and-options/#declaration-errors)); non-Hash input to `new` / `assign_attributes`; positional arguments to `with`; a non-object JSON root | — |
| `KeyError` | an unregistered type name | — |
| `EncodingError` (Oj's class) | malformed JSON in `from_json` | message without the input, no `cause` |
| `NameError` | `use_alias!` with a name already taken | — |

None of these messages contain an input value: they name classes, field names
and declared schema only.

```ruby run
class Payment < FieldStruct::Base
  unknown_attributes :raise
  required :cents, :integer, coercion_policy: :raise
end

coercion = begin
  Payment.new(cents: 'ten')
rescue FieldStruct::CoercionError => e
  e
end
coercion.message      # => "could not coerce String input for cents: Integer fields expect a base-10 integer, got a String that is not one"
coercion.field_name   # => :cents
coercion.original.class # => ArgumentError
coercion.is_a?(FieldStruct::Error) # => true

unknown = begin
  Payment.new(cents: 1, 'cvv' => '123')
rescue FieldStruct::UnknownAttributeError => e
  e
end
unknown.keys    # => [:cvv]
unknown.message # => "unknown attribute(s) for Payment: :cvv"
```

Rescue `FieldStruct::Error` to catch FieldStruct's own runtime errors in one
clause. Declaration errors are plain `ArgumentError` / `KeyError`, raised when
the class body runs.

Upstream: [USAGE, Log safety](https://github.com/Paymentbox-com/field_struct/blob/v0.15.0/USAGE.md#log-safety-error-messages-and-sensitive-fields).
