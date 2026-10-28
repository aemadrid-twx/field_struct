---
title: Build your own adapter
description: Write a TypeScript-types generator for field_struct classes in about 60 lines, on the same walk the official adapters use, and package it as a gem.
sidebar:
  label: Build your own
  order: 5
---

In this tutorial we will write an adapter that turns field_struct classes into
TypeScript interfaces, so a frontend gets types that always match the JSON your
Ruby API sends. It takes about 60 lines, because field_struct does the hard part:
[`FieldStruct::Introspection`](/field_struct/adapters/introspection/) walks a class
and tells you, for each field, its JSON name, whether it is required, and what
shape its value has. The JSON Schema and Avro adapters are built the same way.

## 1. Look at what the walk gives us

Let's start with the classes we want to describe:

```ruby title="models.rb" run
class Author < FieldStruct::Base
  required :name, :string
end

class Book < FieldStruct::Base
  required :title,   :string
  required :price,   :big_decimal
  required :format,  :symbol, enum: %i[hardcover paperback ebook]
  optional :pages,   :integer
  optional :authors, :array, of: Author
  optional :sequel,  Book
  serialize :json, format: 'bookFormat'
end
```

`Introspection.properties` returns one `Property` per field, in declaration order.
Each one has a `key` (the name in the JSON), the `field` (with `required?`,
`default`, `description` and `options`), and a `node` describing the value:

```ruby run
title, price, format, pages, authors, sequel = FieldStruct::Introspection.properties(Book)

format.key                    # => "bookFormat"
title.field.required?         # => true
pages.field.required?         # => false
price.node.class              # => FieldStruct::Introspection::ScalarNode
price.node.type.class         # => FieldStruct::Types::BigDecimal
format.node.options[:enum]    # => [:hardcover, :paperback, :ebook]
authors.node.class            # => FieldStruct::Introspection::ArrayNode
authors.node.element.klass    # => Author
sequel.node.klass             # => Book
```

There are only four kinds of node, so an adapter is a `case` over them:

- **`ScalarNode`**: one value. Its `type` is the field_struct type instance, and
  `options` are the field's options.
- **`ArrayNode`**: `element` is the node for each item, or `nil` when no element
  type is recorded.
- **`UnionNode`**: `members`, one node per type the value may be, in declared order.
- **`StructNode`**: `klass`, another struct class. It is only a reference, never
  expanded for you, which is what makes recursive structs (`sequel`) safe to walk.

## 2. Write the adapter

One method per kind of thing: a class becomes an interface, a node becomes a
TypeScript type, and a scalar maps by its type.

```ruby title="ts_types.rb" run
module TsTypes
  module_function

  # The interfaces for +root+ and every struct it refers to, as one string.
  def generate(root)
    interfaces = {}
    interface(root, interfaces)
    interfaces.values.join("\n\n")
  end

  def interface(klass, interfaces)
    raise ArgumentError, "#{klass.inspect} needs a name; assign it to a constant" unless FieldStruct::Introspection.named?(klass)

    name = klass.name.split('::').last
    return name if interfaces.key?(name)

    interfaces[name] = nil # claim the name first, so a struct that refers to itself stops here
    fields = FieldStruct::Introspection.properties(klass).map do |property|
      type = type_for(property.node, interfaces)
      property.field.required? ? "  #{property.key}: #{type};" : "  #{property.key}?: #{type} | null;"
    end
    interfaces[name] = "export interface #{name} {\n#{fields.join("\n")}\n}"
    name
  end

  def type_for(node, interfaces)
    custom = node.respond_to?(:options) ? node.options.dig(:ts, :type) : nil
    return custom if custom

    case node
    when FieldStruct::Introspection::ArrayNode
      node.element ? "Array<#{type_for(node.element, interfaces)} | null>" : 'unknown[]'
    when FieldStruct::Introspection::UnionNode
      node.members.map { |member| type_for(member, interfaces) }.join(' | ')
    when FieldStruct::Introspection::StructNode then interface(node.klass, interfaces)
    else scalar(node)
    end
  end

  def scalar(node)
    case node.type
    when FieldStruct::Types::Boolean then 'boolean'
    when FieldStruct::Types::Integer, FieldStruct::Types::Float then 'number'
    when FieldStruct::Types::Symbol
      node.options[:enum] ? node.options[:enum].map { |value| %("#{value}") }.join(' | ') : 'string'
    when FieldStruct::Types::String, FieldStruct::Types::BigDecimal,
         FieldStruct::Types::Date, FieldStruct::Types::Time, FieldStruct::Types::DateTime then 'string'
    else 'unknown'
    end
  end
end
```

A few choices to notice, since every adapter makes them:

- **Describe the JSON, not the Ruby object.** A BigDecimal is a `string` because
  `to_json` writes `"24.99"`, and times are strings for the same reason.
- **Order matters in `scalar`.** `:uuid`, `:email` and `:url` are subclasses of
  `Types::String`, so they land on `string` without a branch of their own. A
  custom type you don't know becomes `unknown` instead of a guess.
- **Array elements may be `null`,** because field_struct accepts `nil` elements.
  The official adapters make the same call.

## 3. Run it

```ruby run
puts TsTypes.generate(Book)
```

```ts
export interface Book {
  title: string;
  price: string;
  bookFormat: "hardcover" | "paperback" | "ebook";
  pages?: number | null;
  authors?: Array<Author | null> | null;
  sequel?: Book | null;
}

export interface Author {
  name: string;
}
```

The `serialize :json` name came through (`bookFormat`), the enum became a union of
string literals, and `sequel` refers back to `Book` without looping forever.

## 4. Let fields override the mapping

Sometimes the derived type is not the one you want. The convention every adapter
follows is an option named after the adapter: `avro: {...}` for Avro,
`json_schema: {...}` for JSON Schema, so here `ts: {...}`. field_struct keeps
options it doesn't know and hands them to adapters, and adapters ignore each
other's. `type_for` above already reads `ts: {type:}`:

```ruby run
class Shelf < FieldStruct::Base
  required :label,  :string
  optional :layout, :value, ts: {type: '"grid" | "list"'}
end

TsTypes.generate(Shelf).include?('layout?: "grid" | "list" | null;')   # => true
```

## 5. Test it

Test an adapter the way the official ones are tested:

- **Pin the exact output** for a class that uses every kind of node, so any change
  to it is deliberate.
- **Check it against the real consumer.** The JSON Schema adapter validates real
  `to_json` output against its schemas, and the Avro adapter round-trips every
  instance through the real `avro` gem. Here, that means running `tsc` over the
  output in CI.

```ruby run
expected = <<~TS.chomp
  export interface Book {
    title: string;
    price: string;
    bookFormat: "hardcover" | "paperback" | "ebook";
    pages?: number | null;
    authors?: Array<Author | null> | null;
    sequel?: Book | null;
  }

  export interface Author {
    name: string;
  }
TS

TsTypes.generate(Book) == expected   # => true
```

## 6. Package it as a gem

When it works, make it a gem so apps that don't need it never load it. The
official adapters share a layout you can copy:

- **Name** it after what it extends: `field_struct-typescript`, with
  `require 'field_struct/typescript'` and a `FieldStruct::TypeScript` module.
- **Use module functions** (`FieldStruct::TypeScript.generate(Book)`). Add an
  opt-in `Methods` module if you want `Book.to_typescript`, and never patch
  `FieldStruct::Base`.
- **Depend on a field_struct that has Introspection.** Until that is released,
  fail early with a clear message:

  ```ruby
  require 'field_struct'
  raise LoadError, 'field_struct-typescript needs FieldStruct::Introspection' unless defined?(FieldStruct::Introspection)
  ```

- **Read only the public surface:** `Introspection`, the node classes, `Field`
  (`required?`, `default`, `description`, `sensitive?`, `options`) and the type
  classes. That is what field_struct keeps stable for adapters.

The [field_struct-adapters](https://github.com/aemadrid-twx/field_struct-adapters)
repository is a good starting point to copy: each gem there is one directory,
with its own gemspec, specs, README and CHANGELOG.
