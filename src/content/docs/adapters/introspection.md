---
title: Introspection reference
description: FieldStruct::Introspection, the format-neutral walk over a struct's fields that every adapter is built on.
sidebar:
  label: Introspection reference
  order: 6
---

`FieldStruct::Introspection` is part of core field_struct (on `develop`, in the
next release). It describes a struct class without assuming a target format, for
code that exports structs to another schema language. Everything here is frozen
and read-only.

```ruby title="example.rb" run
class Address < FieldStruct::Base
  required :city, :string
end

class Customer < FieldStruct::Base
  required :name,   :string, description: 'Full legal name'
  optional :tier,   :symbol, enum: %i[free pro], default: :free
  optional :homes,  :array, of: Address
  optional :ref,    :union, of: %i[integer string]
  serialize :json, homes: 'addresses'
end
```

## `Introspection.properties(klass, serialization: :json)`

Returns an `Array` of `Property`, one per field, in declaration order (inherited
fields first). `serialization:` picks the `serialize` format whose external names
become each property's `key`. A format the class doesn't declare keeps the field
names.

```ruby run
properties = FieldStruct::Introspection.properties(Customer)
properties.map(&:key)   # => ["name", "tier", "addresses", "ref"]
FieldStruct::Introspection.properties(Customer, serialization: :xml).map(&:key)  # => ["name", "tier", "homes", "ref"]
```

## `Property`

| Method | Returns |
|---|---|
| `key` | the external name, a `String` |
| `field` | the `FieldStruct::Field` |
| `node` | one of the four node classes below |

The `Field` methods adapters use:

| Method | Returns |
|---|---|
| `name` | the attribute name, a `Symbol` |
| `required?` | `true` for `required` fields |
| `default` | the `default:` value or callable, or `nil` |
| `description` | the `description:` / `desc:` text, or `nil` |
| `sensitive?` | `true` for `sensitive: true` |
| `options` | the field's type and validation options (`enum:`, `format:`…), plus any option field_struct doesn't use itself (an adapter's own `avro:` or `ts:`). `required`, `default`, `description` and `sensitive` are not in it: read them with the methods above |
| `type_instance` | the field_struct type instance |

```ruby run
name, tier = properties
name.field.description   # => "Full legal name"
tier.field.required?     # => false
tier.field.default       # => :free
```

## Nodes

### `ScalarNode`

One value. `type` is the type instance (a `FieldStruct::Types::Base` subclass).
`options` are the field's options (for an array element, its `element:` options).

```ruby run
tier = properties[1].node
tier.type.class          # => FieldStruct::Types::Symbol
tier.options[:enum]      # => [:free, :pro]
```

### `ArrayNode`

`type` and `options` as above. `element` is the node for each item, built the first
time you read it. It is `nil` when no element type is recorded: an array of unions
records only the union class, not its members.

```ruby run
homes = properties[2].node
homes.element.class      # => FieldStruct::Introspection::StructNode
homes.element.klass      # => Address
```

### `UnionNode`

`type` is the union type, and `members` is one node per member type, in declared order.

```ruby run
properties[3].node.members.map { |member| member.type.class }  # => [FieldStruct::Types::Integer, FieldStruct::Types::String]
```

### `StructNode`

`type` is the nested type, and `klass` is the struct class. It is a reference only:
the walk never expands it, so recursion is yours to handle. Track the classes
you've described and stop at one you've seen.

## `Introspection.node(type, options = {})`

The node for a type instance and options, as `properties` builds it. Use it for
types that don't come from a field.

## `Introspection.named?(klass)`

Whether `klass` has a name an exporter can use as a definition key or record name.
An anonymous class has none, and neither does a class defined under an anonymous
module (its name reads `"#<Module:0x…>::Address"`).

```ruby run
FieldStruct::Introspection.named?(Address)                            # => true
FieldStruct::Introspection.named?(Class.new(FieldStruct::Base))       # => false
```

## Stability

`Introspection`, its four node classes and `Property` are public API, like the
rest of field_struct: a breaking change to them comes with a version bump and an
entry in the upgrade guide. Adapters may rely on them and on the `Field` methods
listed above. Anything not listed here is internal.
