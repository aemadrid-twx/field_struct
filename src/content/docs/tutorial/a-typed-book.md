---
title: A typed Book
description: "Chapter 1: define a FieldStruct with typed fields, defaults, validation and coercion."
sidebar:
  label: 1. A typed Book
  order: 2
---

Every bookstore needs books. In this chapter you'll model one as a
`FieldStruct::Base` subclass and see what it does with the data you give it.

## Define the Book

Subclass `FieldStruct::Base` and declare each field with a name, a type and
options:

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

- `required` fields must be present for the book to be valid. `optional` ones may be `nil`.
- The second argument is the type. `:decimal` holds a `BigDecimal`, which is what you want for money.
- The rest are options: `format:` (a regex the string must match), `round:`
  (decimal places), `in:` (allowed range), `enum:` (allowed values) and `default:`.

`in: (0..)` means "zero or more". The parentheses matter: a bare `0..` at the end
of a line makes Ruby read the next line as the end of the range.

## Values are coerced on the way in

Data from a form, a CSV or a query string arrives as strings. FieldStruct
converts each value to the field's type when you assign it:

```ruby run
book = Book.new(isbn: '978-1-68050-981-8', title: 'Eloquent Ruby',
                price: '24.999', pages: '320', format: 'hardcover')
book.price   # => BigDecimal('25.00')
book.pages   # => 320
book.format  # => :hardcover
book.valid?  # => true
```

`'24.999'` became `25.00`: `round: 2` rounds half up. String and symbol keys both
work in `new`.

## Optional fields and defaults

Leave out an optional field and it's `nil`. A field with a `default:` gets that
value instead:

```ruby run
basic = Book.new(isbn: '978-1-68050-981-8', title: 'Eloquent Ruby', price: '24.99')
basic.author      # => nil
basic.format      # => :paperback
basic.attributes  # => { isbn: "978-1-68050-981-8", title: "Eloquent Ruby", price: BigDecimal("24.99"), author: nil, pages: nil, format: :paperback }
```

`attributes` (also `to_h`) gives you every field as a plain Hash. A default can
also be a lambda, such as `default: -> { Time.now }`, which runs once per new
object.

## Validation and errors

With the default settings, bad data doesn't make `new` raise. The object is
created, it just isn't valid, and it tells you why:

```ruby run
bad = Book.new(isbn: 'abc', title: ' ', price: '-5', format: 'audiobook')
bad.valid?           # => false
bad.errors[:isbn]    # => ["is invalid"]
bad.errors[:title]   # => ["is required"]
bad.errors.to_h      # => { isbn: ["is invalid"], title: ["is required"], price: ["is invalid"], format: ["is invalid"] }
bad.errors.full_messages # => ["Isbn is invalid", "Title is required", "Price is invalid", "Format is invalid"]
```

- A required field that's missing reads `"is required"`. For strings, blank or
  whitespace-only counts as missing, so `' '` fails.
- A value that breaks `format:`, `enum:` or `in:` reads `"is invalid"`.

Fields are checked every time you assign them, so fixing a field clears its error:

```ruby run
bad.isbn   = '978-1-68050-981-8'
bad.title  = 'Eloquent Ruby'
bad.price  = '24.99'
bad.format = :ebook
bad.valid? # => true
```

Always check `valid?` before you trust a struct. A required field can still be
`nil` on an invalid object.

## When a value can't be coerced

Some strings just aren't numbers. By default FieldStruct keeps the raw value and
records an error, so nothing is lost:

```ruby run
odd = Book.new(isbn: '978-1-68050-981-8', title: 'Eloquent Ruby', price: '24.99', pages: 'lots')
odd.pages          # => "lots"
odd.valid?         # => false
odd.errors[:pages] # => ["could not be coerced: Integer fields expect a base-10 integer, got a String that is not one"]
```

The message names the type and the input's class, never the value itself, so it's
safe to log. You can change this per class or per field with `coercion_policy`
(`:replace` stores `nil`, `:raise` raises `FieldStruct::CoercionError`); see
[Coercion failure policy](https://github.com/Paymentbox-com/field_struct/blob/v0.15.0/USAGE.md#coercion-failure-policy).

## What you built

A `Book` that:

- declares typed fields, some required and one with a default,
- turns form-style strings into `BigDecimal`, `Integer` and `Symbol` values,
- checks a format, an allowed range and a list of allowed values,
- reports what's wrong in `errors` instead of raising.

The full list of types and options is in the field_struct
[USAGE reference](https://github.com/Paymentbox-com/field_struct/blob/v0.15.0/USAGE.md#types).

**Next:** [Orders and JSON](../orders-and-json/), where books go into an order
and the order goes over the wire as JSON.
