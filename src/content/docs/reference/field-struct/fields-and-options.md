---
title: Fields and options
description: The field, required and optional macros, every option a field takes on any type, and the reserved field names.
sidebar:
  order: 1
---

Fields are declared on a `FieldStruct::Base` subclass with one of three macros.
The type is always the second positional argument; everything after it is a
keyword option.

```ruby
field    name, type, **options   # the primitive; optional unless required: true
required name, type, **options   # same as field ..., required: true
optional name, type, **options   # same as field ..., required: false
```

```ruby run
class Account < FieldStruct::Base
  field    :id,       :integer
  required :email,    :string, format: /@/
  optional :nickname, :string
end

Account.metadata[:id].required?     # => false
Account.metadata[:email].required?  # => true
Account.new(email: 'a@b.co').valid? # => true
Account.new.errors.to_h             # => { email: ["is required"] }
```

- `name` is a Symbol or String; it's stored as a Symbol.
- `type` is a registered name (`:string`, `:decimal`, …), a `FieldStruct::Base`
  subclass (a nested struct), or a `FieldStruct::Types::Base` subclass. See
  [Types](../types/).
- Each macro returns the class's `Metadata`, so a line in IRB prints the
  fields declared so far.
- Every field gets a reader and a setter. The setter coerces and validates;
  see [Validation and errors](../validation-and-errors/).
- Declaring a field again (in the same class or a subclass) replaces the earlier
  declaration.

## Options every field takes

| Option | Value | Default | Effect |
|---|---|---|---|
| `required:` | `true` / `false` | `false` | Presence-checked: a missing value adds `"is required"`. Set by `required` / `optional`. |
| `default:` | any literal, or a callable (Proc, lambda, Method) | `nil` | Applied in `new` when the key is absent. A callable is called once per instance. |
| `coercion_policy:` | `:keep_raw`, `:replace`, `:raise` | `nil` (use the class's) | Per-field override of what happens when coercion fails. |
| `description:` / `desc:` | String | `nil` | Documentation only. Never in `attributes`, `as_json` or pattern matching. Passing both raises. |
| `rbs_type:` | non-blank String of RBS | `nil` | Type that `FieldStruct::RBS` emits for this field. No runtime effect. |
| `sensitive:` | `true` / `false` | `false` | `inspect` shows `[FILTERED]` instead of the value. Data paths are unchanged. |

Every other option belongs to the field's type: `format:`, `enum:`, `in:`,
`round:`, `base:`, `strict:`, `values:`, `zone:`, `of:`, `element:`. The
[Types](../types/) page lists which type takes which.

### `default:`

A default is the value the setter receives when the input doesn't mention the
field. It goes through coercion and validation like any other value, so a
default satisfies `required`.

```ruby run
class Ticket < FieldStruct::Base
  required :priority, :symbol, default: :normal
  optional :tags,     :array, of: :string, default: -> { [] }
  optional :created,  :date, default: -> { Date.new(2026, 1, 1) }
end

t = Ticket.new
t.priority  # => :normal
t.created   # => Date.new(2026, 1, 1)
t.valid?    # => true

Ticket.new.tags.equal?(Ticket.new.tags) # => false
```

The callable runs once per instance, so each `Ticket` gets its own array.
Passing the key explicitly as `nil` skips the default:

```ruby run
Ticket.new(priority: nil).priority  # => nil
Ticket.new(priority: nil).valid?    # => false
```

### `description:` / `desc:`

```ruby run
class Contact < FieldStruct::Base
  required :email, :string, description: 'Primary contact address'
  optional :name,  :string, desc: 'Given name'
end

Contact.metadata[:email].description # => "Primary contact address"
Contact.metadata[:name].desc         # => "Given name"
Contact.new(email: 'a@b.co').to_h    # => { email: "a@b.co", name: nil }
```

### `sensitive:`

`inspect` (and so `pp`, the `errors:` suffix of an invalid instance, and nested
structs) renders the value as `[FILTERED]`. A `nil` still shows as `nil`, so a
missing value stays visible. Readers, `to_h`, `as_json`, `to_json`,
`deconstruct_keys` and equality all use the real value.

```ruby run
class Card < FieldStruct::Base
  required :number, :string, sensitive: true
  optional :cvv,    :string, sensitive: true
  optional :brand,  :string
end

card = Card.new(number: '4111111111111111', brand: 'visa')
card.inspect                       # => '#<Card number: [FILTERED], cvv: nil, brand: "visa">'
card.number                        # => "4111111111111111"
card.to_h[:number]                 # => "4111111111111111"
Card.metadata[:number].sensitive?  # => true
```

### `rbs_type:`

Replaces the type `FieldStruct::RBS.generate` derives for the field. It's not
parsed (the `rbs` gem isn't a runtime dependency), so fully qualify constants.
See [Introspection and tooling](../introspection-and-tooling/#rbs-for-your-classes).

```ruby run
class Report < FieldStruct::Base
  optional :rows, :value, rbs_type: '::Array[::Hash[::Symbol, untyped]]'
end

Report.metadata[:rows].rbs_type # => "::Array[::Hash[::Symbol, untyped]]"
```

## Options a type doesn't know

An option name no registered type uses is **not** an error: it's kept verbatim
in `Field#options` for downstream tooling (an Avro exporter, say). An option
that *another* type uses is an error, because it's almost certainly a mistake.

```ruby run
class Event < FieldStruct::Base
  required :count, :integer, avro: 'long'
end

Event.metadata[:count].options # => { avro: "long" }

err = begin
  Class.new(FieldStruct::Base) { required :count, :integer, enum: [1, 2] }
rescue ArgumentError => e
  e
end
err.message # => "enum: option does not apply to Integer fields. It applies to: String, ImmutableString, Symbol, UUID, URL, Email, Binary."
```

## Declaration errors

These raise `ArgumentError` when the class body runs:

| Cause | Message |
|---|---|
| Reserved field name | `field :errors is reserved: FieldStruct::Base relies on #errors, and a field would shadow it. Pick another name; serialize :json can keep the external key (e.g. serialize :json, errors_field: 'errors').` |
| Unknown type name | `KeyError`: `no FieldStruct type registered for :nope` |
| Option with the wrong shape | `round: on BigDecimal expects Integer, got String ("2")` |
| Option for another family | `enum: option does not apply to Integer fields. It applies to: …` |
| Both `description:` and `desc:` | `pass either description: or desc:, not both` |
| Bad `coercion_policy:` | `unknown coercion policy :foo (expected one of [:keep_raw, :replace, :raise])` |
| Bad `sensitive:` | `sensitive: must be true or false, got Integer` |
| Bad `rbs_type:` | `rbs_type: must be a non-empty String of RBS (e.g. rbs_type: '::ActiveRecord::Relation'), got ""` |
| `:array` without `of:` | `array field requires an `of:` option naming the element type` |
| `:union` without `of:` | `union field requires an `of: [...]` option naming the member types` |
| `:union` with `of:` that isn't an Array | `union `of:` must be an Array of member types` |
| `:union` with fewer than two members | `union `of:` must have at least two members` |
| `:integer` with `base:` outside 2..36 | `base: on Integer expects an Integer from 2 to 36, got 37` |
| `:boolean` with an unknown `values:` preset | `unknown :boolean values preset :nope. Available: [:english_yes_no, :english, :numeric]` |
| `:boolean` with `values:` neither a Hash nor a Symbol | `boolean values: must be a Hash {truthy:, falsy:} or a preset Symbol` |
| `:date` / `:time` / `:datetime` with `format:` of the wrong class | `format: must be a String, Regexp, or Symbol — got Integer` |

An unknown type name raises `KeyError`, not `ArgumentError`.

```ruby run
err = begin
  Class.new(FieldStruct::Base) { required :x, :nope }
rescue KeyError => e
  e
end
err.message # => "no FieldStruct type registered for :nope"
```

## Reserved field names

These names are methods `FieldStruct::Base` calls on its own instances, so a
field by that name would break it. They're listed in
`FieldStruct::Base::RESERVED_FIELD_NAMES`:

`errors`, `attributes`, `attribute_names`, `assign_attributes`, `as_json`,
`to_json`, `to_h`, `to_model`, `model_name`, `inspect`, `hash`, `class`,
`send`, `public_send`, `freeze`, `instance_variable_set`, `initialize`,
`initialize_copy`, `raise`, `with`, `dup`, `deconstruct`, `deconstruct_keys`,
`json_value`, `temporal_json_value`, `apply_defaults`,
`run_cross_field_validators`, `validate_field`, `apply_coercion_policy`,
`record_coercion_failure`.

```ruby run
FieldStruct::Base::RESERVED_FIELD_NAMES.size     # => 30
FieldStruct::Base::RESERVED_FIELD_NAMES.include?(:name)   # => false
```

`name`, `type` and `method` are legal. To read a JSON key with a reserved name,
give the field another name and map it:

```ruby run
class Response < FieldStruct::Base
  optional :errors_field, :array, of: :string
  serialize :json, errors_field: 'errors'
end

Response.from_json('{"errors":["boom"]}').errors_field # => ["boom"]
```

Upstream: [USAGE, Field options](https://github.com/Paymentbox-com/field_struct/blob/v0.15.0/USAGE.md#field-options-any-type).
