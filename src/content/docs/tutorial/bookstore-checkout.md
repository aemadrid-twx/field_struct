---
title: Build a bookstore checkout
description: A hands-on introduction to FieldStruct and Actionable.
sidebar:
  order: 1
---

:::note[Work in progress]
This tutorial is being written. The first step below runs today; the rest is outlined.
:::

In this tutorial you'll build the checkout for a small online bookstore:

1. A `Book` struct: typed fields, coercion, validation.
2. An `Order` with nested line items.
3. A `PlaceOrder` action that checks the order and returns a typed result.

You need Ruby 3.2 or newer and the two gems in your `Gemfile` (see the [home page](../../)).

## Step 1: a Book

```ruby title="book.rb" run
class Book < FieldStruct::Base
  required :isbn,  :string
  required :title, :string
  required :price, :decimal, round: 2
end
```

Values are coerced on the way in, so a price read from a form or a CSV becomes a `BigDecimal`:

```ruby run
book = Book.new(isbn: '978-1-68050-981-8', title: 'Eloquent Ruby', price: '24.99')
book.title   # => "Eloquent Ruby"
book.price   # => BigDecimal('24.99')
book.valid?  # => true
```

A missing required field doesn't raise. The object just isn't valid, and says why:

```ruby run
untitled = Book.new(isbn: '978-1-68050-981-8', price: '5')
untitled.valid?        # => false
untitled.errors[:title] # => ["is required"]
```

## Coming next

- `Order`, holding an array of nested line items.
- `PlaceOrder`, an `Actionable::Action` that turns an order into a success or a failure.
