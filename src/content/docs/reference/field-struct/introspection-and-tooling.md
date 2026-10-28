---
title: Introspection and tooling
description: Metadata and Field, metadata.to_h and describe, RBS for your own classes, and scaffolding a class from JSON.
sidebar:
  order: 9
---

Every FieldStruct class carries its declarations as data, so code (and you, in
a console) can ask what a class looks like without reading its source.

```ruby run
class LineItem < FieldStruct::Base
  required :sku, :string
end

module Shop
  class Order < FieldStruct::Base
    required :id,     :uuid, desc: 'primary key'
    optional :items,  :array, of: LineItem
    optional :tags,   :array, of: :string
    optional :status, :union, of: %i[symbol boolean]
    optional :scope,  :value, rbs_type: '::ActiveRecord::Relation'
    optional :extra,  :value
    optional :total,  :decimal, round: 2, default: 0, sensitive: true
  end
end
```

## `Metadata`

`Klass.metadata` is the class's `FieldStruct::Metadata`. A subclass starts with
a copy of its parent's fields and serializations. Its own declarations win.

| Method | Returns |
|---|---|
| `metadata[name]` | the `Field`, or `nil` (Symbol or String name) |
| `names` | field names in declaration order (also `Klass.attribute_names`) |
| `each` / Enumerable | each `Field`, in order |
| `to_h` | `{name => schema Hash}` of plain values (see below); with a block, `Enumerable#to_h` |
| `describe` | one readable line per field (`Klass.describe` adds the class name) |
| `serializations` | `{format => {field => 'external'}}` |
| `serialization(format)` | one mapping, `{}` when undeclared |
| `inspect` | `#<FieldStruct::Metadata fields=[...]>` (plus `serializations=[...]` when any) |

```ruby run
meta = Shop::Order.metadata
meta.names.first(3)   # => [:id, :items, :tags]
meta['id'].name       # => :id
meta[:nope]           # => nil
meta.count            # => 7
FieldStruct::Metadata.new.inspect # => "#<FieldStruct::Metadata empty>"
```

## `Field`

Each declaration is a frozen `FieldStruct::Field`.

| Method | Returns |
|---|---|
| `name` | Symbol |
| `type` | the type class (`FieldStruct::Types::Nested` / `Union` for nested and union fields) |
| `type_instance` | the type object the setter calls (`type_instance.ruby_type`, `.struct_class` for nested, `.member_types` for unions) |
| `required?` | Boolean |
| `default` | the literal or callable, or `nil` |
| `options` | the type options, frozen, after presets and defaults are resolved (an array's `of:` is stored as `of_type:`) |
| `coercion_policy` | the field's override, or `nil` |
| `description` / `desc` | String or `nil` |
| `rbs_type` | String or `nil` |
| `sensitive?` | Boolean |
| `setter_name` / `ivar_name` | `:total=` / `:@total` |

```ruby run
field = Shop::Order.metadata[:total]
field.type                     # => FieldStruct::Types::BigDecimal
field.required?                # => false
field.default                  # => 0
field.options                  # => { round: 2 }
field.sensitive?               # => true
field.type_instance.ruby_type  # => BigDecimal
field.inspect                  # => "#<FieldStruct::Field :total BigDecimal sensitive default=0 round=2>"
Shop::Order.metadata[:id].options # => { format: /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/i }
```

## `metadata.to_h`

A schema made of plain values, safe to `pp` or dump. Classes and type objects
become short names, a callable default becomes `"<callable>"`. `rbs_type` and
`sensitive` appear only when set.

```ruby run
Shop::Order.metadata.to_h[:id]    # => { type: "UUID", ruby_type: "String", required: true, default: nil, options: { format: /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/i }, description: "primary key" }
Shop::Order.metadata.to_h[:total] # => { type: "BigDecimal", ruby_type: "BigDecimal", required: false, default: 0, options: { round: 2 }, description: nil, sensitive: true }
Shop::Order.metadata.to_h[:status][:ruby_type] # => "Symbol | TrueClass | FalseClass"
Shop::Order.metadata.to_h[:items][:options]    # => { of_type: "Nested" }
```

An array of structs shows its element type as `"Nested"`, without the struct's
name. `describe` names it.

## `describe`

A readable summary: each field's type, required or optional (and `sensitive`),
the options it declares, and the options its type accepts (required ones
starred, presets listed). Array fields also say what `element:` accepts.

```ruby run
puts Shop::Order.describe
Shop::Order.describe.lines[2].strip # => "items (Array, optional) — of_type: Nested(LineItem) — accepts of* (Symbol | Class), element (Hash)"
Class.new(FieldStruct::Base).describe # => "AnonymousFieldStruct\n(no fields)"
```

```text
Shop::Order
  id (UUID, required) — format: /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/i — accepts format (Regexp | Symbol; presets: any_version, v4, v7), enum (Array), strict (TrueClass | FalseClass)
  items (Array, optional) — of_type: Nested(LineItem) — accepts of* (Symbol | Class), element (Hash)
  tags (Array, optional) — of_type: String — accepts of* (Symbol | Class), element (Hash) — element accepts format, enum, strict
  status (Union, optional) — accepts of* (Array)
  scope (Value, optional)
  extra (Value, optional)
  total (BigDecimal, optional, sensitive) — round: 2 — accepts round (Integer), in (Array | Range)
```

## RBS for your classes

The gem ships signatures for its own classes (`sig/field_struct.rbs`). The
readers and setters your `field` declarations define are generated per class by
`FieldStruct::RBS.generate(klass)`:

```ruby run
rbs = FieldStruct::RBS.generate(Shop::Order)
rbs.include?("module Shop\n  class Order < ::FieldStruct::Base")      # => true
rbs.include?('attr_reader id: ::String')                               # => true
rbs.include?('def items=: (::Array[::LineItem]? value) -> ::Array[::LineItem]?') # => true
rbs.include?('attr_reader tags: ::Array[::String?]?')                  # => true
rbs.include?('attr_reader status: (::Symbol | bool)?')                 # => true
rbs.include?('attr_reader scope: ::ActiveRecord::Relation?')           # => true
rbs.include?('def extra=: (untyped value) -> untyped')                 # => true
```

```text
# Generated by FieldStruct::RBS. Types describe a valid instance: an
# invalid one (a required field left unset, or a :keep_raw coercion
# failure holding the raw input) can hold other values. Check valid?.
module Shop
  class Order < ::FieldStruct::Base
    attr_reader id: ::String
    def id=: (::String? value) -> ::String?

    attr_reader items: ::Array[::LineItem]?
    def items=: (::Array[::LineItem]? value) -> ::Array[::LineItem]?

    attr_reader tags: ::Array[::String?]?
    def tags=: (::Array[::String?]? value) -> ::Array[::String?]?

    attr_reader status: (::Symbol | bool)?
    def status=: ((::Symbol | bool)? value) -> (::Symbol | bool)?

    attr_reader scope: ::ActiveRecord::Relation?
    def scope=: (::ActiveRecord::Relation? value) -> ::ActiveRecord::Relation?

    attr_reader extra: untyped
    def extra=: (untyped value) -> untyped

    attr_reader total: ::BigDecimal?
    def total=: (::BigDecimal? value) -> ::BigDecimal?
  end
end
```

The rules:

- **Readers describe a valid instance.** A required field is `T`, an optional
  one `T?`. An invalid instance can hold other values. Check `valid?`.
- **Writers are `(T? value) -> T?`.** Loose input the setter would coerce
  (`order.total = '1.5'`) runs fine in Ruby but is a Steep error.
- **Generics are filled in:** `::Array[::LineItem]`; a scalar element is
  nullable (`of: :string` → `::Array[::String?]`); unions become `(A | B)`,
  with `:boolean` as `bool`; nested structs use their qualified name.
- **`:value`** (and a union with a `:value` member) is `untyped`, without `?`.
- **Overrides:** a field's `rbs_type:` beats the type's `#rbs_type`, which
  beats the derived type. It replaces `T` verbatim, and `?` is still added where it
  would be.
- **Subclasses** emit only their own fields, as `class Sub < ::Parent`.
- **Namespaces** become `module` nesting.
- A custom type whose `ruby_type` is a bare generic (`::Hash`) emits
  `::Hash[untyped, untyped]` unless it defines `rbs_type`.
- Generate RBS for the nested and element classes too, so names like
  `::LineItem` resolve.

```ruby run
class SubOrder < Shop::Order
  required :note, :string
end

FieldStruct::RBS.generate(SubOrder).include?("class SubOrder < ::Shop::Order\n  attr_reader note: ::String") # => true

err = begin
  FieldStruct::RBS.generate(Class.new(FieldStruct::Base))
rescue ArgumentError => e
  e
end
err.message # => "cannot generate RBS for an anonymous class"
```

`FieldStruct::RBS.type_for(field, nullable: nil)` returns one field's type
exactly as `generate` writes it, for other generators. `nullable: nil` follows
`!field.required?`. `untyped` never gets `?`.

```ruby run
items = Shop::Order.metadata[:items]
FieldStruct::RBS.type_for(items)                              # => "::Array[::LineItem]?"
FieldStruct::RBS.type_for(items, nullable: false)             # => "::Array[::LineItem]"
FieldStruct::RBS.type_for(Shop::Order.metadata[:id], nullable: true)   # => "::String?"
FieldStruct::RBS.type_for(Shop::Order.metadata[:extra], nullable: true) # => "untyped"
```

## Scaffolding a class from JSON

`FieldStruct::Scaffold.from_json(input, class_name: 'Generated')` turns example
JSON into starter source you then refine. `input` is a JSON string (an object or
an array of objects), a Hash, or an Array of Hashes.

- A JSON object becomes a nested class, emitted before its parent.
- An array becomes `:array, of: …`.
- `true` / `false` → `:boolean`, an integer → `:integer`, a real → `:float`.
- **Strings stay `:string`**, including numeric-looking ones. The guess goes in a
  trailing comment.
- With several samples, a field is `required` only when it is present and
  non-blank in every one, and small repeated vocabularies get a
  `# values: [...] — enum?` hint.
- A key that is a Ruby keyword or a reserved field name gets a `_field` suffix
  and a `serialize :json` line mapping it back.

```ruby run
source = FieldStruct::Scaffold.from_json('{"name":"Al","age":30,"ref":"00421","errors":1}', class_name: 'User')
puts source
source.include?('required :ref, :string # numeric-looking (e.g. "00421") — :integer? or keep :string if an id/code') # => true
source.include?('serialize :json, errors_field: "errors"') # => true

hints = FieldStruct::Scaffold.from_json('[{"kind":"cc"},{"kind":"ach"},{"kind":"cc"}]')
hints.include?('required :kind, :string # values: ["cc", "ach"] — enum?') # => true
```

```ruby
class User < FieldStruct::Base
  required :name, :string
  required :age, :integer
  required :ref, :string # numeric-looking (e.g. "00421") — :integer? or keep :string if an id/code
  required :errors_field, :integer

  serialize :json, errors_field: "errors"
end
```

An empty array raises `ArgumentError` (`no samples to scaffold from`), and so
does a root that is not an object or an array of objects.

Upstream: [USAGE, Introspection](https://github.com/aemadrid-twx/field_struct/blob/v0.16.0/USAGE.md#introspection) and [RBS for your own classes](https://github.com/aemadrid-twx/field_struct/blob/v0.16.0/USAGE.md#rbs-for-your-own-classes).
