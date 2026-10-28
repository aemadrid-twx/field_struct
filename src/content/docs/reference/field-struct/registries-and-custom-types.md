---
title: Registries and custom types
description: How type names resolve, namespace registries, the Registry API, writing your own type, and use_alias!.
sidebar:
  order: 8
---

A type name like `:string` is looked up in a `FieldStruct::Registry` when the
field is declared. `FieldStruct.types` is the built-in one. A module can expose
its own for the classes inside it.

## How a name resolves

For a class named `Shop::Inner::Order`, `field :total, :money` looks for the
nearest enclosing module that responds to `field_types`, starting with the
innermost (`Shop::Inner`, then `Shop`), and looks the name up in that registry.
If no enclosing module has one, it uses `FieldStruct.types`. Registries can
have a parent, and a lookup that misses walks up the parent chain.

A Class passed as the type (`field :x, Cents`, `field :address, Address`) skips
the registry entirely.

## Namespace registries

```ruby run
class Cents < FieldStruct::Types::Base
  def self.own_option_schema = { currency: option(type: ::String) }

  def coerce(value, currency: 'USD', **)
    return nil if value.nil?
    unless value.is_a?(Numeric) || value.to_s.match?(/\A\d+(\.\d+)?\z/)
      raise ArgumentError, "Cents fields expect a number, got #{value.class}"
    end

    (BigDecimal(value.to_s) * 100).to_i
  end

  def ruby_type = ::Integer
end

module Shop
  def self.field_types
    @field_types ||= FieldStruct.new_registry do
      register :cents, Cents
      register :money, :cents   # an alias to a registered name
    end
  end

  module Inner
    def self.field_types
      @field_types ||= FieldStruct.new_registry(Shop.field_types) { register :tag, :string }
    end

    class Order < FieldStruct::Base
      required :total, :money, currency: 'EUR'
      optional :label, :tag
    end
  end
end

order = Shop::Inner::Order.new(total: '12.34', label: 5)
order.total   # => 1234
order.label   # => "5"
Shop::Inner::Order.new(total: 'x').errors[:total] # => ["could not be coerced: Cents fields expect a number, got String"]
```

Outside `Shop`, `:cents` is not registered:

```ruby run
err = begin
  Class.new(FieldStruct::Base) { field :price, :cents }
rescue KeyError => e
  e
end
err.message # => "no FieldStruct type registered for :cents"
```

## `FieldStruct.new_registry`

```ruby
FieldStruct.new_registry(parent = FieldStruct.types) { register ... }
```

Builds a `Registry` with that parent and evaluates the block inside it, so
`register` needs no receiver. Pass `nil` for a registry with no parent (then
you register every type the namespace needs).

## `Registry` API

| Method | Does |
|---|---|
| `Registry.new(parent = nil)` | an empty registry, optionally parented |
| `register(name, type_class)` | adds a type; returns the registry |
| `register(alias_name, existing_name)` | registers the type `existing_name` resolves to (now) under another name |
| `lookup(name)` | the type class, walking parents; raises `KeyError` (`no FieldStruct type registered for :nope`) |
| `key?(name)` | whether `lookup` would find it |
| `parent` | the parent registry, or `nil` |
| `type_classes` | every distinct type class here and in the parents |

```ruby run
registry = Shop.field_types
registry.key?(:money)                        # => true
registry.key?(:string)                       # => true
registry.lookup(:money)                      # => Cents
registry.parent.equal?(FieldStruct.types)    # => true
registry.inspect                             # => "#<FieldStruct::Registry types=[:cents, :money] parent>"

bare = FieldStruct.new_registry(nil) { register :text, FieldStruct::Types::String }
bare.parent        # => nil
bare.key?(:integer) # => false
```

## Writing a type

A type is a subclass of `FieldStruct::Types::Base`:

| Method | Required | Contract |
|---|---|---|
| `#coerce(value, **options)` | yes | Return the coerced value. Return `nil` for `nil`. Raise `ArgumentError`, `TypeError` or `RangeError` to refuse; the field's coercion policy handles it. The field's options arrive as keywords. |
| `#ruby_type` | yes | The Ruby class (or an Array of classes) a valid value has. Used by `metadata.to_h` and the RBS generator. |
| `#missing?(value)` | no | What `required` refuses. Default: `value.nil?`. |
| `#rbs_type` | no | A String of RBS to emit instead of one derived from `ruby_type` (`'::Hash[::Symbol, ::String]'`). Default `nil`. |
| `.own_option_schema` | no | `{name => option(type: [...], required: false, presets: [])}`. These options are then checked at declaration. Merged with the parent class's schema. |
| `.resolve_options(options)` | no | Rewrite a field's options once, at declaration (for example a preset Symbol into its value). Default: unchanged. |
| `.default_format` | no | If defined, a field with no `format:` gets this one (how `:uuid` / `:url` / `:email` get their regex). |
| `.resolve_format(format)` | no | Expand a declared `format:` into the strftime String `to_json` renders a date or time with. A type with format presets needs it for `to_json` to honour a preset Symbol. Default: a String passes through, a Symbol raises `ArgumentError` (`… has no format presets`). |

Write refusal messages that name the value's class, not its contents, so they
stay safe to log. A Class passed as the type is instantiated once per field.

```ruby run
Class.new(FieldStruct::Base) { field :price, Cents }.new(price: 1).price # => 100

err = begin
  Class.new(FieldStruct::Base) { field :price, Cents, currency: 1 }
rescue ArgumentError => e
  e
end
err.message # => "currency: on Cents expects String, got Integer (1)"
```

To change a built-in's defaults class-wide, subclass it, override the
`default_*` or `presets` method, and register the subclass under a name:

```ruby run
class USDate < FieldStruct::Types::Date
  def self.default_format = '%m/%d/%Y'
end

module Billing
  def self.field_types = @field_types ||= FieldStruct.new_registry { register :us_date, USDate }

  class Invoice < FieldStruct::Base
    required :due, :us_date
  end
end

Billing::Invoice.new(due: '07/03/2026').due # => Date.new(2026, 7, 3)
Billing::Invoice.new(due: '07/03/2026').as_json[:due] # => "07/03/2026"
```

## `use_alias!`

`FieldStruct.use_alias!(name = :FS)` defines a top-level constant pointing at
`FieldStruct` and switches the `inspect` prefix of FieldStruct's own objects
(`Registry`, `Metadata`, `Field`, `Errors`, types) to it. Calling it again with
the same name is fine. A name already taken by something else raises
`NameError`.

```ruby run
FieldStruct.use_alias!(:FS)
FS.equal?(FieldStruct)     # => true
FS::Errors.new.inspect     # => "#<FS::Errors empty>"

err = begin
  FieldStruct.use_alias!(:String)
rescue NameError => e
  e
end
err.message # => "::String is already defined (String); not aliasing FieldStruct"
```

Upstream: [USAGE, Custom types & namespaces](https://github.com/aemadrid-twx/field_struct/blob/v0.16.0/USAGE.md#custom-types--namespaces).
