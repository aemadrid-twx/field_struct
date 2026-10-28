---
title: JSON Schema
description: Publish the JSON a struct writes as a JSON Schema, for LLM and MCP tools, API docs and request validation in other languages.
sidebar:
  order: 2
---

`field_struct-json_schema` turns a struct class into a
[JSON Schema](https://json-schema.org/) (draft 2020-12) of the JSON it writes
with `to_json` and reads back with `from_json`. One Ruby class then describes the
same payload to everything else that needs to know its shape: an LLM deciding how
to call your tool, a TypeScript frontend, a Python service validating what you
send it.

```ruby
gem 'field_struct-json_schema', git: 'https://github.com/aemadrid-twx/field_struct-adapters',
                                glob: 'field_struct-json_schema/*.gemspec'
```

## The schema of a struct

```ruby title="refund.rb" run
require 'field_struct/json_schema'

class RefundRequest < FieldStruct::Base
  required :order_id, :string, format: /\Aord_[0-9a-z]{8}\z/, description: 'The order to refund'
  required :amount,   :big_decimal, round: 2, description: 'In the order currency'
  optional :reason,   :symbol, enum: %i[damaged late duplicate other], default: :other
  optional :notify,   :boolean, default: true
  serialize :json, order_id: 'orderId'
end

schema = FieldStruct::JSONSchema.generate(RefundRequest)

schema['required']                       # => ["orderId", "amount"]
schema['properties']['orderId']['pattern']  # => "^ord_[0-9a-z]{8}$"
schema['properties']['reason']['enum']   # => ["damaged", "late", "duplicate", "other", nil]
schema['properties']['notify']           # => {"type" => ["boolean", "null"], "default" => true}
```

It describes the **canonical JSON**, the JSON that `to_json` writes:

- Property names follow `serialize :json`, so this is `orderId`.
- A BigDecimal is a decimal string, matched by a pattern.
- The Ruby `format:` Regexp became an ECMA-262 `pattern` that matches exactly the
  same strings.
- Optional fields also accept `null`.

[The gem's README](https://github.com/aemadrid-twx/field_struct-adapters/tree/main/field_struct-json_schema)
lists every mapping.

## Use case: an action as an LLM or MCP tool

An LLM tool, or a tool on an MCP server, is a name, a description and a JSON
Schema for its arguments. An actionable action already has all three: its class
name, its `desc`, and its input struct. So the tool definition is one call:

```ruby title="tool.rb" run
class RefundOrder < Actionable::Action
  input do
    required :order_id, :string, description: 'The order to refund, like ord_8f3k2m1q'
    required :amount,   :big_decimal, round: 2
    optional :reason,   :symbol, enum: %i[damaged late duplicate other]
  end

  step :refund

  def refund = succeed!(:refunded)
end

def tool_for(action, description)
  schema = FieldStruct::JSONSchema.generate(action.input)
  {name: action.name.gsub('::', '_'), description: description, input_schema: schema.except('$schema')}
end

tool = tool_for(RefundOrder, 'Refund part or all of an order')
tool[:name]                                   # => "RefundOrder"
tool[:input_schema]['required']               # => ["order_id", "amount"]
tool[:input_schema]['properties']['reason']['enum']  # => ["damaged", "late", "duplicate", "other", nil]
```

When the model calls the tool, its arguments go straight to `RefundOrder.run`,
which coerces and validates them like any other input. The schema tells the model
what to send, and the action still checks it. [RubyLLM](https://rubyllm.com) accepts
any object that responds to `to_json_schema` as tool parameters, so including
`FieldStruct::JSONSchema::Methods` in a struct lets you pass the class itself
there.

## Use case: validate a payload in another service

The schema is a contract other languages can check. Here a validator that is not
field_struct ([json_schemer](https://github.com/davishmcclurg/json_schemer), a
standalone JSON Schema validator) accepts what Ruby writes and rejects a payload
the struct would reject too:

```ruby run
require 'json_schemer'

validator = JSONSchemer.schema(FieldStruct::JSONSchema.generate(RefundRequest))
request = RefundRequest.new(order_id: 'ord_8f3k2m1q', amount: '12.5', reason: :late)

validator.valid?(JSON.parse(request.to_json))                       # => true
validator.valid?({'orderId' => 'ORDER-1', 'amount' => '12.50'})     # => false
RefundRequest.new(order_id: 'ORDER-1', amount: '12.50').valid?      # => false
```

In a TypeScript service the same schema works with
[Ajv](https://ajv.js.org/), and tools like `json-schema-to-typescript` turn it into
interfaces. Write it to a file in CI and the frontend's types can never drift
from the Ruby class:

```ruby
File.write('schemas/refund_request.json', JSON.pretty_generate(FieldStruct::JSONSchema.generate(RefundRequest)))
```

## Use case: API documentation

OpenAPI 3.1 uses JSON Schema 2020-12 for its schemas, so a generated schema can
go under `components.schemas` as it is (drop `$schema`). Nested structs come
along in `$defs`, under their class names.

## Overrides

When the derived schema is not what you want, give a field a `json_schema:`
option, or define `json_schema` on a custom type:

```ruby run
class Money < FieldStruct::Types::Base
  def coerce(value, **) = Rational(value)
  def ruby_type = Rational
  def json_schema = {'type' => 'string', 'pattern' => '^[0-9]+/[0-9]+$'}
end

class Split < FieldStruct::Base
  required :share, Money
  optional :meta,  :value, json_schema: {'type' => 'object'}
end

properties = FieldStruct::JSONSchema.generate(Split)['properties']
properties['share']  # => {"type" => "string", "pattern" => "^[0-9]+/[0-9]+$"}
properties['meta']   # => {"type" => ["object", "null"]}
```

## Limits

The schema follows field_struct's own validation, so it accepts exactly what the
struct accepts:

- An optional string field with `enum:` or `format:` also accepts a blank string,
  because a blank value counts as missing there.
- Every array element may be `null`, because validation skips `nil` elements.
- `:array, of: :uuid` doesn't check each element's format unless you add
  `element: {format: …}`.
- A Regexp that has no exact ECMA-262 translation (an atomic group, a backreference,
  `\p{…}`) is not approximated. It is kept as `x-ruby-pattern`, an annotation that
  validators ignore.
