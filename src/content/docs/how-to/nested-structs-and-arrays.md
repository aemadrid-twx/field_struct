---
title: How to validate nested structs and arrays
description: Model a payload with nested objects and lists, and find out which element is wrong.
sidebar:
  label: Nested structs and arrays
  order: 6
---

Use a struct class as a field's type to nest it, and `:array, of:` for a list.
Hashes are coerced into the nested class at every level.

## 1. Declare the shape

```ruby title="invoice.rb" run
class InvoiceLine < FieldStruct::Base
  required :sku,      :string
  required :quantity, :integer, in: (1..)
end

class Invoice < FieldStruct::Base
  required :number, :string
  required :lines,  :array, of: InvoiceLine
  optional :tags,   :array, of: :string, element: { format: /\A[a-z-]+\z/ }
end
```

`element:` takes the options a single field of that type would take and checks
every element with them.

## 2. Find the bad elements

A list of scalars reports the bad positions by index (0-based):

```ruby run
invoice = Invoice.new(
  number: 'INV-7',
  lines: [{ sku: 'A-1', quantity: 2 }, { sku: 'B-2', quantity: 0 }, { sku: '', quantity: 1 }],
  tags: %w[rush Gift paid]
)

invoice.valid?          # => false
invoice.errors[:tags]   # => ["element at index 1 is invalid"]
```

A list of structs only says `"is invalid"` on the parent. Each element has its
own errors, so ask them:

```ruby run
invoice.errors[:lines]  # => ["is invalid"]

invoice.lines.each_with_index.reject { |line, _| line.valid? }.to_h { |line, i| [i, line.errors.to_h] }  # => { 1 => { quantity: ["is invalid"] }, 2 => { sku: ["is required"] } }
```

That gives you a per-element error map you can send back to a client. A
required array that is empty counts as missing:

```ruby run
Invoice.new(number: 'INV-8', lines: []).errors[:lines]  # => ["is required"]
```

## 3. Re-assign after changing a child in place

Validity is worked out when a field is assigned. If you fix (or break) a nested
struct in place, the parent doesn't notice until you assign the field again:

```ruby run
invoice.lines[1].quantity = 1
invoice.lines[2].sku = 'C-3'
invoice.tags = %w[rush gift paid]

# Stale: lines was never re-assigned, so it still reports the old errors.
invoice.valid?                 # => false
invoice.lines = invoice.lines  # re-assign: the setter checks every element again
invoice.valid?                 # => true
```

For nested structs you change often, declare them `immutable!` and use `with`
to make changed copies. Then every change goes through a setter.

## See also

- field_struct USAGE: [Nested, arrays, unions](https://github.com/Paymentbox-com/field_struct/blob/v0.15.0/USAGE.md#nested-arrays-unions), [Element options](https://github.com/Paymentbox-com/field_struct/blob/v0.15.0/USAGE.md#element-options-element), [Validity is computed on assignment](https://github.com/Paymentbox-com/field_struct/blob/v0.15.0/USAGE.md#validity-is-computed-on-assignment-shallow-valid-staleness)
- Tutorial: [Orders and JSON](../../tutorial/orders-and-json/#nest-a-struct-inside-a-struct)
