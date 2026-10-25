---
title: Orders and JSON
description: "Chapter 2: nest structs inside structs, round-trip through JSON, rename JSON keys and mask sensitive values."
sidebar:
  label: 2. Orders and JSON
  order: 3
---

A customer buys more than one book at a time. In this chapter you'll put books
into line items, line items into an `Order`, and send the order over the wire as
JSON.

## Where we left off

This chapter starts from the `Book` you built in
[chapter 1](../a-typed-book/):

<details>
<summary>The <code>Book</code> class from chapter 1</summary>

```ruby title="book.rb" run
class Book < FieldStruct::Base
  required :isbn,   :string, format: /\A[\d-]{10,17}\z/
  required :title,  :string
  required :price,  :decimal, round: 2, in: (0..)
  optional :author, :string
  optional :pages,  :integer
  optional :format, :symbol, enum: %i[paperback hardcover ebook], default: :paperback
end
```

</details>

## Nest a struct inside a struct

To nest one struct in another, use the class as the field's type. For a list,
use `:array, of:` with the element type:

```ruby title="order.rb" run
class LineItem < FieldStruct::Base
  required :book,     Book
  required :quantity, :integer, in: (1..)

  def subtotal = book.price * quantity # `def name = expr`: Ruby's one-line method
end

class Order < FieldStruct::Base
  required :number,        :string
  required :email,         :email
  required :lines,         :array, of: LineItem
  optional :placed_on,     :date
  optional :payment_token, :string, sensitive: true

  def total = lines.sum(&:subtotal)
end
```

A struct is still a plain Ruby class, so you can add your own methods, like
`subtotal` and `total`. The `:email` type is a string with a built-in email
format check. You'll meet `sensitive: true` [below](#keep-secrets-out-of-your-logs).

You can build the whole tree from plain hashes, the way it arrives from a form
or an API. Each level is coerced into its own class:

```ruby run
order = Order.new(
  number: 'A-1001',
  email: 'ann@example.com',
  placed_on: '2026-10-24',
  payment_token: 'tok_4242',
  lines: [
    { book: { isbn: '978-1-68050-981-8', title: 'Eloquent Ruby', price: '24.99' }, quantity: 2 },
    { book: { isbn: '978-1-93778-549-9', title: 'Practical Object-Oriented Design', price: '39.95', format: 'ebook' }, quantity: '1' }
  ]
)

order.lines.first.class        # => LineItem
order.lines.first.book.title   # => "Eloquent Ruby"
order.lines.last.quantity      # => 1
order.placed_on                # => Date.new(2026, 10, 24)
order.total                    # => BigDecimal('89.93')
order.valid?                   # => true
```

You can also pass an existing `Book` or `LineItem` instead of a hash.

## Invalid children make the parent invalid

If a nested struct is invalid, the parent is too. The parent reports
`"is invalid"` on that field; ask the child for the details:

```ruby run
empty_line = Order.new(
  number: 'A-1002',
  email: 'ann@example.com',
  lines: [{ book: { isbn: '978-1-68050-981-8', title: 'Eloquent Ruby', price: '24.99' }, quantity: 0 }]
)

empty_line.valid?                          # => false
empty_line.errors[:lines]                  # => ["is invalid"]
empty_line.lines.first.errors[:quantity]   # => ["is invalid"]
```

A required `:array` also counts as missing when it's empty, so an order with
`lines: []` reports `lines` as `"is required"`.

:::caution
Validity is worked out when a field is **assigned**. If you change a nested
struct in place (`order.lines.first.quantity = 0`), the order doesn't notice.
Assign the field again (`order.lines = order.lines`) to re-check it. See
[shallow `valid?` staleness](https://github.com/Paymentbox-com/field_struct/blob/v0.15.0/USAGE.md#validity-is-computed-on-assignment-shallow-valid-staleness).
:::

## To JSON and back

`to_json` turns the whole tree into a JSON string, and `from_json` reads it back
into objects:

```ruby run
json = order.to_json
json.start_with?('{"number":"A-1001","email":"ann@example.com","lines":[{"book"') # => true

copy = Order.from_json(json)
copy == order                # => true
copy.lines.first.book.price  # => BigDecimal('24.99')
```

Two structs are `==` when they're the same class with the same attributes. Here
is that JSON, pretty-printed:

```json
{
  "number": "A-1001",
  "email": "ann@example.com",
  "lines": [
    {
      "book": { "isbn": "978-1-68050-981-8", "title": "Eloquent Ruby", "price": "24.99",
                "author": null, "pages": null, "format": "paperback" },
      "quantity": 2
    },
    {
      "book": { "isbn": "978-1-93778-549-9", "title": "Practical Object-Oriented Design", "price": "39.95",
                "author": null, "pages": null, "format": "ebook" },
      "quantity": 1
    }
  ],
  "placed_on": "2026-10-24",
  "payment_token": "tok_4242"
}
```

Prices become strings, so no precision is lost, and dates become ISO 8601.
`as_json` gives you the same data as a Hash, ready for a JSON renderer:

```ruby run
order.as_json[:placed_on]                    # => "2026-10-24"
order.as_json[:lines].first[:book][:price]   # => "24.99"
order.as_json[:lines].first[:book][:format]  # => "paperback"
```

## Use the JSON keys your API expects

Say your API's clients expect camelCase keys like `orderNumber`. Map each field to
its external name with `serialize :json`. In `order.rb` you would add this line
inside `class Order`, after the fields. Here we reopen the class to add it:

```ruby run
class Order
  serialize :json, number: 'orderNumber', placed_on: 'placedOn', payment_token: 'paymentToken'
end

order.as_json.keys  # => [:orderNumber, :email, :lines, :placedOn, :paymentToken]
order.to_h.keys     # => [:number, :email, :lines, :placed_on, :payment_token]

Order.from_json('{"orderNumber":"A-1003","email":"bo@example.com","lines":[{"book":{"isbn":"978-1-68050-981-8","title":"Eloquent Ruby","price":"24.99"},"quantity":1}]}').number # => "A-1003"
Order.from_json(order.to_json) == order  # => true
```

- The mapping works both ways: `to_json` and `as_json` write the external names,
  `from_json` reads them.
- `to_h`, `attributes` and `new` always use the Ruby names.
- Fields you don't list (`email`, `lines`) keep their names. Each nested class
  uses its own mapping, so give `Book` a `serialize :json` line too if it needs one.

## Keep secrets out of your logs

`payment_token` was declared with `sensitive: true`. It's hidden wherever the
object gets printed or logged, but your code can still read it:

```ruby run
order.inspect.include?('[FILTERED]')  # => true
order.inspect.include?('tok_4242')    # => false
order.payment_token                   # => "tok_4242"
```

:::caution
`sensitive: true` only masks `inspect` and `pp`. The data paths, `to_h`,
`as_json` and `to_json`, still carry the real value, so a JSON round trip keeps
working:

```ruby run
order.to_json.include?('tok_4242')  # => true
```

Filter it yourself before you log JSON or send it to a browser, for example
`order.as_json.except(:paymentToken)`. `as_json` and `to_json` take no
`only:` / `except:` options.
:::

## What you built

- A `LineItem` that nests a `Book`, and an `Order` that holds an array of line items.
- An order you can build from plain hashes, with validation that reaches every level.
- A JSON round trip with your own key names.
- A payment token that stays out of `inspect` output.

More on nested structs, arrays and JSON in the field_struct
[README](https://github.com/Paymentbox-com/field_struct/blob/v0.15.0/README.md#nested-fieldstructs).

**Next:** [Placing the order](../placing-the-order/), where an Actionable action
checks stock and turns an order into a success or a failure.
