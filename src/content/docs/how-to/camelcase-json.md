---
title: How to use camelCase JSON keys
description: Keep snake_case field names in Ruby while reading and writing the key names an external API uses.
sidebar:
  label: Use camelCase JSON keys
  order: 3
---

Your Ruby code wants `first_name`; the API sends and expects `firstName`. Map
each field to its external name with `serialize :json`.

## 1. Map the fields

List each field whose JSON name differs. Fields you leave out keep their own
name:

```ruby title="customer.rb" run
class Address < FieldStruct::Base
  required :street_line, :string
  required :postal_code, :string

  serialize :json, street_line: 'streetLine', postal_code: 'postalCode'
end

class Customer < FieldStruct::Base
  required :first_name, :string
  required :email,      :email
  optional :address,    Address

  serialize :json, first_name: 'firstName'
end
```

Each class carries its own mapping, so a nested struct (`Address` here) needs
its own `serialize :json` line.

## 2. Read and write JSON

`from_json` reads the external names; `to_json` and `as_json` write them:

```ruby run
json = '{"firstName":"Ann","email":"ann@example.com","address":{"streetLine":"1 Main St","postalCode":"84601"}}'

customer = Customer.from_json(json)
customer.first_name            # => "Ann"
customer.address.postal_code   # => "84601"

customer.to_json == json       # => true
customer.as_json.keys          # => [:firstName, :email, :address]
```

## 3. Use Ruby names everywhere else

The mapping applies to JSON only. `new`, the readers and `to_h` use the Ruby
names:

```ruby run
Customer.new(first_name: 'Bo', email: 'bo@example.com').first_name  # => "Bo"
customer.to_h.keys                                                  # => [:first_name, :email, :address]
```

So pass external names to `from_json`, not to `new`. `new` doesn't know
`firstName` and drops it, like any unknown key:

```ruby run
Customer.new(firstName: 'Bo', email: 'bo@example.com').valid?  # => false
```

## A field named like a reserved method

Some names can't be fields because `FieldStruct::Base` uses them itself
(`errors`, `attributes`, `hash`, `class`, …). Give the field another name and
map it back to the JSON key:

```ruby run
class ImportRow < FieldStruct::Base
  optional :errors_field, :string
  serialize :json, errors_field: 'errors'
end

ImportRow.from_json('{"errors":"bad date"}').errors_field  # => "bad date"
ImportRow.new(errors_field: 'none').to_json                # => '{"errors":"none"}'
```

## See also

- field_struct USAGE: [JSON & serialization](https://github.com/Paymentbox-com/field_struct/blob/v0.15.0/USAGE.md#json--serialization), [Gotchas](https://github.com/Paymentbox-com/field_struct/blob/v0.15.0/USAGE.md#gotchas--invariants) (reserved field names)
- Tutorial: [Orders and JSON](../../tutorial/orders-and-json/#use-the-json-keys-your-api-expects)
