---
title: JSON and serialization
description: as_json, to_json and from_json, how values are converted, and serialize mappings for external key names.
sidebar:
  order: 7
---

FieldStruct reads and writes JSON with [Oj](https://github.com/ohler55/oj)
(`mode: :compat`), never the stdlib `JSON`.

| Method | Returns |
|---|---|
| `record.as_json` | a Hash with Symbol keys, JSON-ready values, and the `:json` mapping applied |
| `record.to_json` | `as_json` dumped to a String |
| `Klass.from_json(string)` | a new instance: parse, reverse-map `:json` names, then `new` |

`as_json` and `to_json` accept an argument (so Rails can pass options) but
ignore it.

## Value conversions in `as_json`

| Value | Becomes |
|---|---|
| `nil`, `true`, `false`, String, Integer, Float | itself |
| Symbol | String |
| BigDecimal | plain-notation String (`"1.5"`, never `"0.15e1"`) |
| Date, Time, DateTime | the field's `format:` (`strftime`, or RFC 3339 for `:iso8601`); ISO 8601 when none |
| Array | each element converted |
| Hash (in a `:value` field) | each value converted, keys kept |
| nested FieldStruct | its own `as_json`, with its own mapping |
| anything else | its `as_json` if it has one, else itself |

```ruby run
class Address < FieldStruct::Base
  required :zip_code, :string
  serialize :json, zip_code: 'zipCode'
end

class Person < FieldStruct::Base
  required :first_name, :string
  optional :kind,       :symbol
  optional :balance,    :decimal
  optional :born,       :date
  optional :address,    Address
  optional :homes,      :array, of: Address
  serialize :json, first_name: 'firstName'
end

alice = Person.new(first_name: 'Alice', kind: :admin, balance: '1.50', born: '1990-07-03',
                   address: { zip_code: '84601' }, homes: [{ zip_code: '84602' }])

alice.as_json # => { firstName: "Alice", kind: "admin", balance: "1.5", born: "1990-07-03", address: { zipCode: "84601" }, homes: [{ zipCode: "84602" }] }
alice.to_json # => '{"firstName":"Alice","kind":"admin","balance":"1.5","born":"1990-07-03","address":{"zipCode":"84601"},"homes":[{"zipCode":"84602"}]}'
alice.to_h.keys.first # => :first_name
```

## `from_json`

Parses the string, renames any external `:json` keys to field names (at every
nesting level, using each class's own mapping), then calls `new`. So coercion,
nested construction, `unknown_attributes` and `coercion_policy` all apply as
they do for `new`. Canonical names still work as keys.

```ruby run
restored = Person.from_json(alice.to_json)
restored == alice                # => true
restored.address.zip_code        # => "84601"
Person.from_json('{"first_name":"Bob"}').first_name # => "Bob"
```

**Round trip.** `Klass.from_json(record.to_json) == record` for every type
except `:value`, which has no type information to restore: Symbols come back
as Strings, Hash keys as Strings.

```ruby run
class Loose < FieldStruct::Base
  optional :data, :value
end

Loose.from_json(Loose.new(data: { k: :v }).to_json).data # => { "k" => "v" }
```

**Decimals.** JSON numbers with a fraction or exponent are parsed as
`BigDecimal`, never through a Float, so a `:decimal` field gets the exact digits
sent. A `:float` field still converts to Float. A `:value` field (and numbers
inside its Hashes and Arrays) holds the `BigDecimal`, which `to_json` writes
back as a string.

```ruby run
class Ledger < FieldStruct::Base
  optional :amount, :decimal
  optional :ratio,  :float
  optional :raw,    :value
end

l = Ledger.from_json('{"amount":1234567890123.4567,"ratio":1.5,"raw":1.25}')
l.amount  # => BigDecimal('1234567890123.4567')
l.ratio   # => 1.5
l.raw     # => BigDecimal('1.25')
l.to_json # => '{"amount":"1234567890123.4567","ratio":1.5,"raw":"1.25"}'
```

**Errors.**

| Input | Raises |
|---|---|
| malformed JSON | Oj's error class (an `EncodingError`), message `from_json could not parse its input as JSON (<reason> at line L, column C)`, without the input and without a `cause` |
| a non-object root (`[...]`, `"hi"`, `42`, `null`) | `ArgumentError`: `from_json expects a JSON object root, got Array` |
| unknown keys under `unknown_attributes :raise` | `FieldStruct::UnknownAttributeError` |
| a bad value under `coercion_policy :raise` | `FieldStruct::CoercionError` |

```ruby run
err = begin
  Person.from_json('{"firstName":')
rescue EncodingError => e
  e
end
err.message # => "from_json could not parse its input as JSON (unexpected character at line 1, column 13)"
err.cause   # => nil

err = begin
  Person.from_json('[1]')
rescue ArgumentError => e
  e
end
err.message # => "from_json expects a JSON object root, got Array"
```

## `serialize`

Maps field names to external names for one format. The mapping works both
ways: `as_json` / `to_json` write the external names, `from_json` reads them.

```ruby
serialize format_name, field_name: 'externalName', ...
```

- Keys are field names, which must already be declared (declare fields first),
  or it raises `ArgumentError`: `serialize :json references undeclared field(s):
  :y. Declare fields before calling serialize.`
- Values are external names. Symbols are converted to Strings.
- Fields not listed keep their own name.
- `attributes` / `to_h` always use field names. Pattern matching too.
- Declaring the same format again replaces the earlier mapping. A subclass
  inherits its parent's mappings, and redeclaring a format replaces it there.
- Several formats can coexist. Only `:json` is used by the gem. Read any other
  from `Klass.metadata.serializations` (for a CSV or XML exporter, say).
- Struct members of a `:union` use their own mapping too. `from_json` tries the
  members in order, so give struct members `unknown_attributes :raise` if the
  union must tell them apart.

```ruby run
class Export < FieldStruct::Base
  required :first_name, :string
  serialize :json, first_name: 'firstName'
  serialize :csv,  first_name: :FIRST
end

Export.metadata.serializations   # => { json: { first_name: "firstName" }, csv: { first_name: "FIRST" } }
Export.metadata.serialization(:csv)  # => { first_name: "FIRST" }
Export.metadata.serialization(:xml)  # => {}

class ExportV2 < Export
  serialize :json, first_name: 'given_name'
end

ExportV2.new(first_name: 'Al').to_json # => '{"given_name":"Al"}'
Export.new(first_name: 'Al').to_json   # => '{"firstName":"Al"}'
```

Upstream: [USAGE, JSON & serialization](https://github.com/aemadrid-twx/field_struct/blob/v0.16.0/USAGE.md#json--serialization).
