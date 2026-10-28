---
title: Avro
description: Write structs as compact Avro binary with a schema, for Kafka topics, data lakes and schema registries, and read old events after the class changes.
sidebar:
  order: 3
---

`field_struct-avro` gives a struct class an [Apache Avro](https://avro.apache.org/)
record schema, and turns instances into Avro binary and back. Avro is what Kafka
pipelines, schema registries and data lakes (Spark, BigQuery, Snowflake) expect:
compact binary, a schema that travels separately, and rules for evolving that
schema without breaking old data.

```ruby
gem 'field_struct-avro', git: 'https://github.com/aemadrid-twx/field_struct-adapters',
                         glob: 'field_struct-avro/*.gemspec'
```

## The schema of a struct

```ruby title="invoice.rb" run
require 'field_struct/avro'

module Billing
  class Line < FieldStruct::Base
    required :sku,   :string
    required :cents, :integer
  end

  class Invoice < FieldStruct::Base
    required :id,     :uuid
    required :total,  :big_decimal, round: 2
    required :issued, :time, zone: 'America/Denver'
    required :status, :symbol, enum: %i[open paid void]
    optional :lines,  :array, of: Line
  end
end

schema = FieldStruct::Avro.schema(Billing::Invoice)

schema['name']        # => "Invoice"
schema['namespace']   # => "Billing"
fields = schema['fields'].to_h { |field| [field['name'], field['type']] }
fields['total']   # => {"type" => "bytes", "logicalType" => "decimal", "precision" => 38, "scale" => 2}
fields['issued']  # => {"type" => "long", "logicalType" => "timestamp-micros"}
fields['status']  # => {"type" => "enum", "name" => "Invoice_status", "symbols" => ["open", "paid", "void"]}
```

The mapping keeps what matters downstream:

- `round: 2` decimals become Avro decimals with that scale, so warehouses read
  them as exact numbers and not as floats.
- Times are microsecond timestamps.
- `enum:` symbols become an Avro enum.
- `Billing::Line` becomes a named record in the `Billing` namespace.

[The gem's README](https://github.com/aemadrid-twx/field_struct-adapters/tree/main/field_struct-avro)
has the full mapping table.

## Use case: publish an event to Kafka

Encoding gives Avro binary, much smaller than the JSON for the same invoice. It
loses nothing on the way back: decimals stay exact, 64-bit integers stay whole,
and times keep their microseconds.

```ruby run
invoice = Billing::Invoice.new(
  id: '0b9d6a4e-3c1f-4a59-9d1e-2f6a8c7b5e10', total: '1249.90', issued: '2026-10-27 09:30:00.123456',
  status: :paid, lines: [{sku: 'BOOK-1', cents: 124_990}]
)

bytes = FieldStruct::Avro.encode(invoice)
bytes.bytesize < invoice.to_json.bytesize   # => true

back = FieldStruct::Avro.decode(Billing::Invoice, bytes)
back == invoice                 # => true
back.total                      # => BigDecimal('1249.90')
back.issued.usec                # => 123456
back.issued.utc_offset          # => -6 * 3600
```

Avro timestamps carry no time zone, so decoding puts the field's `zone:` back.
`issued` comes back in Denver time, just as it went in.

With a schema registry (Confluent's, or Redpanda's), you register the schema once
and prefix each message with its id. Your Kafka client and registry client do
that part:

```ruby
schema_id = registry.register('billing.invoices-value', JSON.generate(FieldStruct::Avro.schema(Billing::Invoice)))
payload   = [0, schema_id].pack('CN') + FieldStruct::Avro.encode(invoice) # Confluent wire format
producer.produce(topic: 'billing.invoices', payload: payload, key: invoice.id)
```

`FieldStruct::Avro.to_datum(invoice)` gives the plain Hash the `avro` gem
writes, for when you use your own writer, like `avro_turf`.

## Use case: read old events after the class changes

Events outlive the code that wrote them. When a newer version of the class
adds a field, pass the schema the old bytes were written with, and Avro fills
the new field from its default:

```ruby run
module V1
  class Signup < FieldStruct::Base
    required :email, :string
  end
end

module V2
  class Signup < FieldStruct::Base
    required :email, :string
    optional :referrer, :string
  end
end

old_bytes  = FieldStruct::Avro.encode(V1::Signup.new(email: 'ana@example.com'))
old_schema = FieldStruct::Avro.schema(V1::Signup).merge('namespace' => 'V2')

signup = FieldStruct::Avro.decode(V2::Signup, old_bytes, writer_schema: old_schema)
signup.email      # => "ana@example.com"
signup.referrer   # => nil
```

Adding an optional field, or a required one with a literal default
(`default: 'none'`), is a safe change; a default given as a lambda can't go in
the schema, so old bytes then fail to decode. A schema registry set to
backward compatibility checks that for you.
Renaming a field isn't: Avro matches fields by name. (The namespace is set to
`V2` here only because this example keeps both versions in one process; in a
real app the class keeps its name.)

## It raises rather than lose data

Avro has fixed-size types, and some values don't fit. The adapter raises instead
of truncating:

```ruby run
class Reading < FieldStruct::Base
  required :at, :time
end

precise = Reading.new(at: '2026-10-27T09:30:00.123456789Z')
error = begin
  FieldStruct::Avro.encode(precise)
rescue ArgumentError => e
  e
end
error.message.include?('more precision than timestamp-micros')   # => true

FieldStruct::Avro.decode(Reading, FieldStruct::Avro.encode(precise, timestamp: :nanos), timestamp: :nanos).at.nsec  # => 123456789
```

The same goes for a decimal with more digits than its declared precision, and an
integer past 64 bits.

## Options

- Per call: `serialization:` (which `serialize` names become Avro field names)
  and `timestamp:` (`:micros`, `:nanos` or `:millis`).
- Per field, `avro: {...}`:
  - `type:` replaces the field's mapping entirely;
  - `timestamp:` sets the precision for that field;
  - `precision:` and `scale:` set a decimal's;
  - `enum: false` gives a plain string instead of an enum;
  - `enum_default:` lets readers handle symbols you add later.
- `include FieldStruct::Avro::Methods` adds `Klass.to_avro_schema`, `#to_avro` and
  `Klass.from_avro`.

A `:big_decimal` without `round:` has no fixed scale, so it travels as a string.
Add `round:` if you want an Avro decimal.
