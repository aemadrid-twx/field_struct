---
title: How to keep sensitive values out of logs
description: Mask card numbers, tokens and passwords in inspect output, and filter them out of JSON you log.
sidebar:
  label: Keep secrets out of logs
  order: 4
---

Mark a field `sensitive: true` and its value is masked wherever the object gets
printed. Your code still reads the real value.

## 1. Mark the fields

```ruby title="card.rb" run
class Card < FieldStruct::Base
  required :number, :string, sensitive: true
  optional :cvv,    :string, sensitive: true
  optional :brand,  :string
end

class Payment < FieldStruct::Base
  required :amount, :decimal
  required :card,   Card
end
```

## 2. Check what gets printed

`inspect` shows `[FILTERED]`, and so do `pp` and Ruby's `Logger`, which call `inspect` on the objects they print. A `nil` still shows
as `nil`, so a missing value stays visible. Masking follows nested structs:

```ruby run
card = Card.new(number: '4111111111111111', brand: 'visa')

card.inspect   # => '#<Card number: [FILTERED], cvv: nil, brand: "visa">'
card.number    # => "4111111111111111"

payment = Payment.new(amount: '9.99', card: card)
payment.inspect.include?('4111')  # => false
```

Error messages never echo input values either, sensitive or not, so an invalid
object is safe to print too.

## 3. Filter JSON yourself

`to_h`, `as_json` and `to_json` carry the real values. They have to, or a JSON
round trip would lose data:

```ruby run
card.to_json.include?('4111')  # => true
```

Before you log JSON, or send it to a browser, drop the sensitive fields. The
field metadata knows which they are:

```ruby run
def loggable(struct)
  hidden = struct.class.metadata.select(&:sensitive?).map(&:name)
  struct.as_json.except(*hidden)
end

loggable(card)  # => { brand: "visa" }
```

This helper filters one level and uses Ruby field names. If the struct nests
others, or maps names with `serialize :json`, walk the nested structs and use
the mapped key names too.

## See also

- field_struct USAGE: [Log safety: error messages and sensitive fields](https://github.com/Paymentbox-com/field_struct/blob/v0.15.0/USAGE.md#log-safety-error-messages-and-sensitive-fields), [Field options](https://github.com/Paymentbox-com/field_struct/blob/v0.15.0/USAGE.md#field-options-any-type)
- Tutorial: [Keep secrets out of your logs](../../tutorial/orders-and-json/#keep-secrets-out-of-your-logs)
