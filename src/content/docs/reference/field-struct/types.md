---
title: Types
description: Every built-in type, what it coerces from, the options it takes, and what counts as missing.
sidebar:
  order: 2
---

The second argument to `field` / `required` / `optional` names the type. These
are registered in `FieldStruct.types`:

```ruby run
FieldStruct.types.inspect # => "#<FieldStruct::Registry types=[:string, :immutable_string, :integer, :float, :big_decimal, :decimal, :boolean, :date, :time, :datetime, :value, :array, :symbol, :uuid, :url, :email, :union, :binary]>"
```

`nil` always coerces to `nil`. "Missing" is what a `required` field refuses
with `"is required"`.

| Name | Holds | Coerces from | Options | Missing when |
|---|---|---|---|---|
| `:string` | `String` | anything, via `to_s` | `format:` `enum:` `strict:` | nil, empty or whitespace-only |
| `:immutable_string` | frozen `String` | as `:string`, then frozen | `format:` `enum:` `strict:` | as `:string` |
| `:symbol` | `Symbol` | Symbol, String | `enum:` | nil |
| `:uuid` | `String` | as `:string` | `format:` (default regex, presets) `enum:` `strict:` | as `:string` |
| `:url` | `String` | as `:string` | `format:` (default regex, presets) `enum:` `strict:` | as `:string` |
| `:email` | `String` | as `:string` | `format:` (default regex, presets) `enum:` `strict:` | as `:string` |
| `:binary` | `String`, ASCII-8BIT | as `:string`, re-encoded | `format:` `enum:` `strict:` | nil or empty (whitespace counts as data) |
| `:integer` | `Integer` | Integer, base-10 String (or `base:`), other numerics truncated | `in:` `base:` `strict:` | nil |
| `:float` | `Float` | Float, `Kernel.Float` forms (base 10 only) | `round:` `in:` | nil |
| `:big_decimal` / `:decimal` | `BigDecimal` | BigDecimal, Integer, Float, numeric String | `round:` `in:` | nil |
| `:boolean` | `true` / `false` | `true`, `false`, `1`, `0`, accepted strings | `values:` | nil (`false` is present) |
| `:date` | `Date` | String, Date, DateTime, Time | `format:` `in:` | nil |
| `:time` | `Time` | String, Time, Date, DateTime | `format:` `in:` `zone:` | nil |
| `:datetime` | `DateTime` | String, DateTime, Date, Time | `format:` `in:` `zone:` | nil |
| `:value` | anything | passed through untouched | none | nil |
| `:array` | `Array` | Array, each element coerced | `of:` (required) `element:` | nil or empty |
| `:union` | first member that accepts it | tries each member in order | `of:` (required, ≥ 2) | nil |
| a `FieldStruct::Base` subclass | that class | instance, or a Hash | none | nil |

Dates and times have their own page: [Dates, times and zones](../dates-and-times/).

## Which option goes with which type

| Option | Value | Types |
|---|---|---|
| `format:` | Regexp, or a preset Symbol | `:string`, `:immutable_string`, `:uuid`, `:url`, `:email`, `:binary` |
| `format:` | strftime String, or a preset Symbol | `:date`, `:time`, `:datetime` |
| `enum:` | Array of allowed values | `:string`, `:immutable_string`, `:symbol`, `:uuid`, `:url`, `:email`, `:binary` |
| `in:` | Array (membership) or Range (`cover?`) | `:integer`, `:float`, `:big_decimal`, `:date`, `:time`, `:datetime` |
| `strict:` | `true` / `false` | `:string` and its subtypes, `:integer` |
| `round:` | Integer (decimal places) | `:float`, `:big_decimal` |
| `base:` | Integer 2..36 | `:integer` |
| `values:` | `{truthy:, falsy:}` Hash, or a preset Symbol | `:boolean` |
| `zone:` | `"UTC"`, `"±HH:MM"`, or an IANA name | `:time`, `:datetime` |
| `of:` | element type (Symbol or Class) | `:array` |
| `of:` | Array of member types | `:union` |
| `element:` | Hash of the element type's options | `:array` |

Using an option on a type outside its family raises `ArgumentError` when the
class loads, naming the types it does apply to. A wrong-shaped value (`round:
'2'`) raises too. See [Fields and options](../fields-and-options/#declaration-errors).

`format:`, `enum:` and `in:` are checked after coercion. A failure adds one
`"is invalid"`, however many of them failed. `nil` is never checked against
them.

### Asking a type what it accepts

Each type class answers `option_schema`, so you don't have to trust this page:

```ruby run
FieldStruct.types.lookup(:date).option_schema # => { format: { type: [String, Symbol], required: false, presets: [:iso8601, :us, :eu] }, in: { type: [Array, Range], required: false, presets: [] } }

FieldStruct::Types::Integer.option_schema.keys # => [:in, :base, :strict]
FieldStruct::Types::Array.option_schema[:of]   # => { type: [Symbol, Class], required: true, presets: [] }
FieldStruct::Types::Value.option_schema        # => {}
```

## Strings

`:string` calls `to_s` on whatever it gets. `:immutable_string` also freezes
the result. Whitespace-only counts as missing.

```ruby run
class Note < FieldStruct::Base
  required :title, :string
  optional :code,  :immutable_string
  optional :state, :string, enum: %w[draft final]
  optional :slug,  :string, format: /\A[a-z-]+\z/
end

n = Note.new(title: :hello, code: 'ab', state: 'other', slug: 'Bad Slug')
n.title          # => "hello"
n.code.frozen?   # => true
n.errors.to_h    # => { state: ["is invalid"], slug: ["is invalid"] }
Note.new(title: '   ').errors[:title] # => ["is required"]
```

### `strict: true`

By default `:string` accepts anything (`12.0.to_s`, `{a: 1}.to_s`). With
`strict: true` it accepts only a String, a Symbol, an Integer, or an object
responding to `to_str`. Anything else is a coercion failure. It applies to
`:immutable_string`, `:uuid`, `:url`, `:email` and `:binary` too.

```ruby run
class Ref < FieldStruct::Base
  required :id, :string, strict: true
end

Ref.new(id: 12345).id   # => "12345"
Ref.new(id: :ord_1).id  # => "ord_1"
Ref.new(id: 12.0).errors[:id] # => ["could not be coerced: String fields with strict: true expect a String, Symbol, Integer or an object responding to #to_str, got a Float"]
```

Strict only narrows: what it accepts becomes exactly what the default would make
of it.

### `:symbol`

Takes a Symbol or a String (via `to_sym`). Anything else is a coercion failure.
An empty string becomes `:""`, which is not missing.

```ruby run
class Placement < FieldStruct::Base
  required :position, :symbol, enum: %i[before after]
end

Placement.new(position: 'after').position     # => :after
Placement.new(position: 'middle').errors.to_h # => { position: ["is invalid"] }
Placement.new(position: 1).errors.to_h        # => { position: ["could not be coerced: expected Symbol or String, got Integer"] }
```

### `:uuid`, `:url`, `:email`

These are `:string` with a default `format:` regex filled in. A value that
doesn't match is `"is invalid"` (a validation error, not a coercion error). Your
own `format:` (a Regexp or one of the presets) replaces the default.

| Type | Preset | Regexp |
|---|---|---|
| `:uuid` | `:any_version` (default) | `/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/i` |
| | `:v4` | `/\A\h{8}-\h{4}-4\h{3}-[89ab]\h{3}-\h{12}\z/i` |
| | `:v7` | `/\A\h{8}-\h{4}-7\h{3}-[89ab]\h{3}-\h{12}\z/i` |
| `:url` | `:http` (default) | `%r{\Ahttps?://[^\s/$.?#][^\s]*\z}i` |
| | `:https_only` | `%r{\Ahttps://[^\s/$.?#][^\s]*\z}i` |
| | `:any_scheme` | `%r{\A[a-z][a-z0-9+\-.]*://[^\s/$.?#][^\s]*\z}i` |
| `:email` | `:default` (default) | `/\A[^@\s]+@[^@\s]+\.[^@\s]+\z/` |
| | `:permissive` | `/\A[^@\s]+@[^@\s]+\z/` |
| | `:strict` | `/\A[\w.+-]+@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+\z/` |

```ruby run
class Profile < FieldStruct::Base
  optional :id,      :uuid, format: :v4
  optional :site,    :url
  optional :feed,    :url, format: :any_scheme
  optional :email,   :email
  optional :login,   :email, format: :permissive
end

p1 = Profile.new(site: 'ftp://example.com', feed: 'ftp://example.com', email: 'a@b', login: 'a@b')
p1.errors.to_h # => { site: ["is invalid"], email: ["is invalid"] }

FieldStruct::Types::UUID.presets.keys  # => [:any_version, :v4, :v7]
FieldStruct::Types::Email.default_format # => /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/
```

An unknown preset raises at declaration: `unknown :uuid format preset :v9.
Available: [:any_version, :v4, :v7]`.

A Symbol `format:` on plain `:string` (or `:immutable_string` / `:binary`) is
accepted by the option check but has no presets to resolve against, so it
validates nothing:

```ruby run
class Loose < FieldStruct::Base
  optional :code, :string, format: :v4
end

Loose.new(code: 'anything').valid? # => true
```

### `:binary`

Coerces like `:string`, then forces the encoding to ASCII-8BIT. Only `nil` and
empty count as missing, because whitespace bytes are data.

```ruby run
class Blob < FieldStruct::Base
  required :bytes, :binary
end

Blob.new(bytes: 'é').bytes.encoding  # => Encoding::ASCII_8BIT
Blob.new(bytes: 'é').bytes.bytesize  # => 2
Blob.new(bytes: '  ').valid?         # => true
```

## Numbers

### `:integer`

| Input | Result |
|---|---|
| Integer | itself |
| String | parsed in base 10 (or `base:`). Surrounding whitespace and digit underscores are fine. `"010"` is 10, not octal; `"0x1A"`, `"3.14"`, `"1e3"` are refused. |
| Float, BigDecimal, Rational | truncated (`12.7` → 12) |
| NaN, ±Infinity | refused |
| Time | its epoch seconds |
| anything else (`true`, a Hash, …) | refused |

```ruby run
class Counts < FieldStruct::Base
  optional :n,    :integer
  optional :code, :integer, base: 16
  optional :page, :integer, in: [10, 20, 30]
end

Counts.new(n: ' 1_000 ').n   # => 1000
Counts.new(n: '010').n       # => 10
Counts.new(n: 12.7).n        # => 12
Counts.new(code: '1A').code  # => 26
Counts.new(page: '25').errors.to_h # => { page: ["is invalid"] }
Counts.new(n: '3.14').errors[:n]   # => ["could not be coerced: Integer fields expect a base-10 integer, got a String that is not one"]
```

`base:` must be an Integer from 2 to 36 (checked at declaration) and only
affects strings.

With `strict: true`, a numeric is accepted only when it is a whole number
(`12.0`, `BigDecimal("12")`, `Rational(24, 2)`); `12.7` and a `Time` are
refused instead of truncated. Strings follow the same rules in both modes.

```ruby run
class Cents < FieldStruct::Base
  required :cents, :integer, strict: true
end

Cents.new(cents: 1250.0).cents        # => 1250
Cents.new(cents: 12.5).errors[:cents] # => ["could not be coerced: Integer fields with strict: true expect a whole number, got a Float that is not one"]
```

| Input | `:integer` | `:integer, strict: true` |
|---|---|---|
| `"42"` | 42 | 42 |
| `12.0` / `BigDecimal("12.0")` | 12 | 12 |
| `12.7` / `Rational(25, 2)` | 12 (truncated) | refused |
| `"12.7"` / `"12.0"` / `"1e3"` / `"0x1A"` | refused | refused |
| `Time` | epoch seconds | refused |
| `Float::NAN` / `Float::INFINITY` | refused | refused |

### `:float`

Reads anything `Kernel.Float` reads, except hex strings: `"1_000.5"`, `" 2.5 "`,
`"1e3"`, `".5"` and `"017"` (17.0) all work; `"0x1A"` is refused. NaN and
±Infinity are refused.

### `:big_decimal` / `:decimal`

Takes a BigDecimal, an Integer, a numeric String, or a Float (converted with 15
significant digits, `Float::DIG`, so `0.1` becomes `0.1`, not
`0.1000000000000000055…`). NaN and ±Infinity are refused.

### `round:`

On `:float` and `:big_decimal`. Rounds **half up** (ties away from zero) to the
given number of places, after coercion. The value keeps its type, so `round: 0`
still returns a Float / BigDecimal. `:decimal` ignores the process-wide
`BigDecimal.mode`.

```ruby run
class Price < FieldStruct::Base
  optional :amount, :decimal, round: 2
  optional :ratio,  :float,   round: 2
  optional :whole,  :decimal, round: 0
end

Price.new(amount: '12.345').amount  # => BigDecimal('12.35')
Price.new(ratio: '2.345').ratio     # => 2.35
Price.new(whole: '2.5').whole       # => BigDecimal('3')
Price.new(amount: 0.1).amount       # => BigDecimal('0.1')
Price.new(amount: 'Infinity').errors[:amount] # => ["could not be coerced: BigDecimal fields expect a finite number, got a non-finite String"]
Price.new(ratio: '0x1A').errors[:ratio]       # => ["could not be coerced: Float fields expect a base-10 number, got a String that is not one"]
```

## `:boolean`

Accepts `true`, `false`, `1` and `0` (anything `== 1` or `== 0`), and strings
from the accepted lists, compared case-insensitively. The default lists are
`%w[true 1]` and `%w[false 0]`, so `"yes"` is refused unless you pick a preset.

| `values:` preset | Truthy | Falsy |
|---|---|---|
| (none) | `true 1` | `false 0` |
| `:english_yes_no` | `true yes y on 1` | `false no n off 0` |
| `:english` | `true yes y on 1` | `false no n off 0` |
| `:numeric` | `1` | `0` |

A Hash `values: {truthy: [...], falsy: [...]}` **replaces** the lists; the
defaults don't still apply.

```ruby run
class Flags < FieldStruct::Base
  optional :active, :boolean
  optional :paid,   :boolean, values: :english_yes_no
  optional :switch, :boolean, values: { truthy: %w[on], falsy: %w[off] }
end

Flags.new(active: '1').active   # => true
Flags.new(paid: 'YES').paid     # => true
Flags.new(switch: 'off').switch # => false
Flags.new(active: 'yes').errors[:active] # => ["could not be coerced: Boolean fields expect true, false, 1, 0 or one of the strings \"true\", \"1\", \"false\", \"0\", got a String that is not one"]
Flags.new(switch: 'true').valid? # => false
```

## `:value`

No coercion, no options. `missing?` is nil-only. Use it when you want a field in
the metadata without committing to a shape. It's the one type that doesn't
survive a JSON round trip with its Ruby type intact; see
[JSON and serialization](../json-and-serialization/).

## `:array`

`of:` names the element type: a registered Symbol, a `FieldStruct::Base`
subclass, or a `Types::Base` subclass. Each element is coerced through it. A
required array is missing when `nil` or empty.

```ruby run
class LineItem < FieldStruct::Base
  required :sku, :string
end

class Basket < FieldStruct::Base
  required :items, :array, of: LineItem
  optional :ids,   :array, of: :integer
end

b = Basket.new(items: [{ sku: 'A1' }], ids: ['1', 2])
b.items.first.sku  # => "A1"
b.ids              # => [1, 2]
Basket.new(items: []).errors[:items] # => ["is required"]
Basket.new(items: [{ sku: '' }]).errors[:items] # => ["is invalid"]
```

A refused element fails the whole field, and the message names the index
(0-based), never the value. Up to five indexes are listed, then a count:

```ruby run
Basket.new(items: [], ids: ['1', 'x']).errors[:ids] # => ["could not be coerced: element at index 1: Integer fields expect a base-10 integer, got a String that is not one"]

Basket.new(items: [], ids: %w[a b c d e f g]).errors[:ids] # => ["could not be coerced: elements at index 0, 1, 2, 3, 4 and 2 more (index 0 shown): Integer fields expect a base-10 integer, got a String that is not one"]
```

Pushing onto an array in place (`basket.ids << 'x'`) skips coercion. Assign the
field again to coerce it; see [Validation and errors](../validation-and-errors/#validity-is-computed-on-assignment).

### `element:`

Options for each element go in `element:`, never on the field. It takes what a
scalar field of the element type would take: coercion options (`strict:`,
`base:`, `round:`, `format:`, `zone:`, `values:`) and validation options
(`format:` Regexp, `enum:`, `in:`). Field-level options (`required:`,
`default:`, `coercion_policy:`, `sensitive:`, …) stay on the field.

```ruby run
class Batch < FieldStruct::Base
  optional :ids,   :array, of: :integer, element: { strict: true, base: 16 }
  optional :days,  :array, of: :date,    element: { format: '%d/%m/%Y' }
  optional :codes, :array, of: :string,  element: { format: /\A[A-Z]{3}\z/ }
end

Batch.new(ids: %w[ff 10]).ids                    # => [255, 16]
Batch.new(codes: %w[USD eur]).errors[:codes]     # => ["element at index 1 is invalid"]
Batch.new(codes: %w[usd EUR gbp]).errors[:codes] # => ["elements at index 0, 2 are invalid"]
Batch.new(days: ['22/10/2026']).as_json[:days]   # => ["22/10/2026"]
```

`element:` is checked at declaration against the element type's own schema.
Unlike a field, it passes nothing through:

| Mistake | Message |
|---|---|
| wrong shape | `in element: of array field :ids, base: on Integer expects Integer, got String ("16")` |
| option the element type lacks | `in element: of array field :x, round: is not an Integer option. Integer accepts: in, base, strict.` |
| a field option | `in element: of array field :x, default: is a field option, not an element option. Declare it on the field itself.` |
| array of arrays | `in element: of array field :x, element options are not supported for Array elements` |
| array of structs | `in element: of array field :x, strict: is not a Nested option. Nested accepts no options.` |

## `:union`

`of:` is an Array of at least two member types (Symbols or Classes). The value
goes to each member in order and the first one that coerces it wins, so order
matters when members overlap. If none accepts it, that's a coercion failure.
A non-finite Float or BigDecimal is refused before any member is tried, so a
`:string` member can't store `"NaN"`.

```ruby run
class Ids < FieldStruct::Base
  optional :int_first, :union, of: %i[integer string]
  optional :str_first, :union, of: %i[string integer]
  optional :strict,    :union, of: %i[integer date]
end

Ids.new(int_first: '42').int_first   # => 42
Ids.new(str_first: '42').str_first   # => "42"
Ids.new(strict: 'zz').errors[:strict] # => ["could not be coerced: no union member (Integer | Date) could coerce String input"]
```

Members are coerced with no options: a union passes none of the field's options
to them.

## Nested structs

Pass a `FieldStruct::Base` subclass as the type. The setter accepts `nil`, an
instance of that class (or a subclass), or a Hash, which it hands to `new`.

```ruby run
class Address < FieldStruct::Base
  required :city, :string
end

class Person < FieldStruct::Base
  required :address, Address
end

Person.new(address: { city: 'NYC' }).address.city # => "NYC"
Person.new(address: { city: '' }).errors[:address] # => ["is invalid"]
Person.new(address: 5).errors[:address]            # => ["could not be coerced: expected Address or Hash, got Integer"]
```

An invalid nested struct marks the parent field `"is invalid"`. Read
`parent.address.errors` for the details. Errors raised inside the nested `new`
(such as `UnknownAttributeError`) propagate to the caller instead of going
through the parent's `coercion_policy`.

## Custom types

Any `FieldStruct::Types::Base` subclass can be a type. See
[Registries and custom types](../registries-and-custom-types/).

Upstream: [USAGE, Types](https://github.com/Paymentbox-com/field_struct/blob/v0.15.0/USAGE.md#types).
