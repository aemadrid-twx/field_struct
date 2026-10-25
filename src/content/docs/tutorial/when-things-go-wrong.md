---
title: When things go wrong
description: "Chapter 4: handle every outcome of an action at the call site, with skips, declared failures, invalid input, errors as data and pattern matching."
sidebar:
  label: 4. When things go wrong
  order: 5
---

`PlaceOrder` works when the books are in stock. Real checkouts also get orders
that were already placed, books that ran out and forms full of typos. In this
chapter you'll make each of those a clear outcome, and handle every one of
them where you call the action.

## Where we left off

This chapter uses the `Book`, `LineItem` and `Order` classes and the `STOCK`
hash from [chapter 3](../placing-the-order/):

<details>
<summary>The classes and stock from chapters 1 to 3</summary>

```ruby title="order.rb" run
class Book < FieldStruct::Base
  required :isbn,   :string, format: /\A[\d-]{10,17}\z/
  required :title,  :string
  required :price,  :decimal, round: 2, in: (0..)
  optional :author, :string
  optional :pages,  :integer
  optional :format, :symbol, enum: %i[paperback hardcover ebook], default: :paperback
end

class LineItem < FieldStruct::Base
  required :book,     Book
  required :quantity, :integer, in: (1..)

  def subtotal = book.price * quantity
end

class Order < FieldStruct::Base
  required :number,        :string
  required :email,         :email
  required :lines,         :array, of: LineItem
  optional :placed_on,     :date
  optional :payment_token, :string, sensitive: true

  serialize :json, number: 'orderNumber', placed_on: 'placedOn', payment_token: 'paymentToken'

  def total = lines.sum(&:subtotal)
end

STOCK = { '978-1-68050-981-8' => 3, '978-1-93778-549-9' => 1 }
```

</details>

## Four outcomes and an exception

Every call to `PlaceOrder.run` ends in one of these:

| What happened | Result class | `status` | `code` |
|---|---|---|---|
| The order was placed | `Actionable::Success` | `:success` | `:success` |
| There was nothing to do | `Actionable::Skipped` | `:skipped` | a skip code you declare |
| A rule of your business said no | `Actionable::Failure` | `:failure` | a failure code you declare |
| The input didn't match the `input` block | `Actionable::Failure` | `:failure` | `:invalid_input` |

And then there's the case that isn't an outcome at all: a bug or an outage
that raises an exception. You'll see all five in this chapter.

## Skip an order that was already placed

A customer double-clicks "Place order", or a retry sends the same order twice.
Charging them twice would be wrong, but so would calling it a failure: the
order *is* placed. That's what a **skip** is for: the action had nothing to do.

Here's `PlaceOrder` again with the new lines marked. It remembers placed order
numbers in `PLACED` (a database table in a real store) and skips any order it
has already seen:

```ruby title="place_order.rb" run ins={1,4-6,15,20-24,29,31-32,41}
PLACED = []

class PlaceOrder < Actionable::Action
  fails :out_of_stock, 'a book in the order is out of stock', http_status: 409
  fails :invalid_input, http_status: 422
  skips :already_placed, 'this order was already placed'

  input { required :order, Order }

  output do
    required :order_number, :string
    required :total,        :decimal
  end

  step :check_duplicate
  step :check_stock
  step :reserve_copies
  step :confirm

  def check_duplicate
    return unless PLACED.include?(input.order.number)

    skip!(:already_placed, nil, order_number: input.order.number, total: input.order.total)
  end

  def check_stock
    input.order.lines.each do |line|
      left = STOCK.fetch(line.book.isbn, 0)
      next unless left < line.quantity

      fail!(:out_of_stock, "only #{left} left of #{line.book.title}",
            lines: "#{line.book.isbn} has #{left} left")
    end
  end

  def reserve_copies
    input.order.lines.each { |line| STOCK[line.book.isbn] -= line.quantity }
  end

  def confirm
    PLACED << input.order.number
    @order_number = input.order.number
    @total        = input.order.total
    succeed("Order #{@order_number} placed")
  end
end
```

What's new:

- **`skips :already_placed, '…'`** declares a skip code with a default message,
  the way `fails` declares a failure code. Once an action declares a skip, it can
  only skip with declared codes.
- **`skip!`** records the skip and stops, so `check_stock` and
  `reserve_copies` never run. Its keyword arguments become the result's output,
  so the caller still learns the order number and total.
- **`http_status: 409`** after a failure's message is *metadata*: a free-form
  Hash Actionable stores on the result and never reads. Your app decides what
  the keys mean. You'll use it to pick an HTTP status in a moment.
- **`fails :invalid_input, http_status: 422`** attaches metadata to the
  `:invalid_input` failure that Actionable builds itself.
- **`fail!`'s keyword arguments** become the result's `errors`, keyed like
  validation errors. Here `lines:` says which book ran short.

Place an order, then place it again:

```ruby run
order = Order.new(
  number: 'A-1001',
  email: 'ann@example.com',
  lines: [
    { book: { isbn: '978-1-68050-981-8', title: 'Eloquent Ruby', price: '24.99' }, quantity: 2 },
    { book: { isbn: '978-1-93778-549-9', title: 'Practical Object-Oriented Design', price: '39.95' }, quantity: 1 }
  ]
)

placed = PlaceOrder.run(order: order)
placed.success?      # => true

again = PlaceOrder.run(order: order)
again.skipped?       # => true
again.failure?       # => false
again.status         # => :skipped
again.code           # => :already_placed
again.message        # => "this order was already placed"
again.order_number   # => "A-1001"
STOCK                # => { '978-1-68050-981-8' => 1, '978-1-93778-549-9' => 0 }
```

The stock only went down once. In chapter 3 the second run was an
`:out_of_stock` failure; now the action knows it has seen this order before.

`ok?` is true for a success *and* a skip, and false only for a failure. Use it
when "nothing to do" is as good as "done":

```ruby run
placed.ok?   # => true
again.ok?    # => true
```

Don't count on a skip's output being complete. Actionable fills it from the
keyword arguments (and any matching instance variables) but only validates the
output of a success.

## The failures

A new order for two copies of *Eloquent Ruby*, with only one left, is a declared
failure. A broken order is `:invalid_input`:

```ruby run
short = Order.new(
  number: 'A-1002',
  email: 'bo@example.com',
  lines: [{ book: { isbn: '978-1-68050-981-8', title: 'Eloquent Ruby', price: '24.99' }, quantity: 2 }]
)

sold_out = PlaceOrder.run(order: short)
sold_out.code      # => :out_of_stock
sold_out.message   # => "only 1 left of Eloquent Ruby"

bad = PlaceOrder.run(order: { number: 'A-1003', email: 'not-an-email', lines: [] })
bad.code           # => :invalid_input
bad.message        # => "input failed validation"
```

## Handle every outcome with `case`/`in`

Results support Ruby's pattern matching. A pattern like
`Actionable::Failure(code: :out_of_stock, message:)` checks the class, matches
`code` and binds `message` to a local variable. Patterns can reach into the
output too:

```ruby run
def checkout_message(result)
  case result
  in Actionable::Success(output: { order_number:, total: })
    "Thanks! Order #{order_number} comes to $#{total.to_s('F')}."
  in Actionable::Skipped(code: :already_placed, output: { order_number: })
    "Order #{order_number} was already placed. Nothing more to do."
  in Actionable::Failure(code: :out_of_stock, message:)
    "Sorry, #{message}."
  in Actionable::Failure(code: :invalid_input)
    "Please check your order: #{result.errors.full_messages.join(', ')}"
  end
end

checkout_message(placed)    # => "Thanks! Order A-1001 comes to $89.93."
checkout_message(again)     # => "Order A-1001 was already placed. Nothing more to do."
checkout_message(sold_out)  # => "Sorry, only 1 left of Eloquent Ruby."
checkout_message(bad)       # => "Please check your order: Order is invalid"
```

A result matches on `code`, `message`, `output` and `history`. `errors` and
`metadata` aren't pattern keys, so read them off the result, as the last branch
does.

There's no `else`, on purpose. If the action someday gains an outcome this
method doesn't handle, `case`/`in` raises `NoMatchingPatternError` instead of
quietly doing the wrong thing:

```ruby run
surprise = Actionable::Failure.new(code: :card_declined)

begin
  checkout_message(surprise)
rescue NoMatchingPatternError => e
  e.class   # => NoMatchingPatternError
end
```

`Actionable::Failure.new` builds a result by hand, without running an action,
which is handy for trying out code like this. Actionable's own codes can
reach any action that has the matching block: `:invalid_input` with an `input`
block, and `:invalid_output` with an `output` block (a success whose output
breaks it). Decide whether your handler needs a branch for them.

## Errors as data

`message` is a sentence for people. Everything else on a result is data your
code can use without parsing that sentence.

`errors` holds the keyword arguments of `fail!`, or the input's validation
errors for `:invalid_input`. It's the same errors object a FieldStruct has:

```ruby run
sold_out.errors[:lines]        # => ["978-1-68050-981-8 has 1 left"]
sold_out.errors.to_h           # => { lines: ["978-1-68050-981-8 has 1 left"] }
bad.errors.to_h                # => { order: ["is invalid"] }
bad.errors.full_messages       # => ["Order is invalid"]
```

`metadata` is what you declared next to the code. Failures and skips have it;
one declared without metadata, or not declared at all, gives `{}`. A success has
no `metadata`:

```ruby run
sold_out.metadata   # => { http_status: 409 }
bad.metadata        # => { http_status: 422 }
again.metadata      # => {}
```

So a JSON endpoint can choose its status from the declaration instead of a
hand-written table:

```ruby run
def http_status(result)
  return 200 if result.ok? # a success or a skip

  result.metadata.fetch(:http_status, 500)
end

http_status(placed)    # => 200
http_status(again)     # => 200
http_status(sold_out)  # => 409
http_status(bad)       # => 422
```

`to_h` turns the whole result into a plain Hash, ready to log or send:

```ruby run
sold_out.to_h[:code]     # => :out_of_stock
sold_out.to_h[:errors]   # => { lines: ["978-1-68050-981-8 has 1 left"] }
again.to_h[:output]      # => { order_number: "A-1001", total: BigDecimal('89.93') }
```

## Exceptions are not outcomes

Every outcome so far is one you declared or one Actionable makes for bad input.
A bug, a lost database connection or a timeout isn't any of those, so
Actionable doesn't turn it into a result. The exception goes straight up to the
caller, the same as in any other Ruby method.

To see it, break the stock: a frozen Hash can't be changed, so
`reserve_copies` raises:

```ruby run
STOCK['978-1-68050-981-8'] = 10
STOCK.freeze

fresh = Order.new(
  number: 'A-1004',
  email: 'cy@example.com',
  lines: [{ book: { isbn: '978-1-68050-981-8', title: 'Eloquent Ruby', price: '24.99' }, quantity: 1 }]
)

begin
  PlaceOrder.run(order: fresh)
rescue FrozenError => e
  e.class   # => FrozenError
end

PLACED    # => ["A-1001"]
```

`check_stock` passed, `reserve_copies` raised, and `confirm` never ran. Nothing
was undone, though: an action has no transaction of its own. If `reserve_copies`
had changed some rows before it raised, they would stay changed. With
ActiveRecord, Actionable's Rails adapter can wrap a run in a transaction; see
[Rails adapter](https://github.com/Paymentbox-com/actionable/blob/v1.9.0/USAGE.md#rails-adapter).

Let exceptions reach your error tracker. Rescue one inside a step only when it's
a case you can name, and turn it into a declared failure with `fail!`.

## What you built

- A `PlaceOrder` that skips an order it has already placed, so a retry is safe.
- A handler that matches every outcome with `case`/`in`, and raises if a new
  one appears.
- An HTTP status read from metadata declared next to each failure code.
- A clear line between outcomes (results you handle) and exceptions (bugs and
  outages you let raise).

More on skips, metadata and the verbs in the actionable
[USAGE reference](https://github.com/Paymentbox-com/actionable/blob/v1.9.0/USAGE.md#declared-skips).

**Next:** [Composing actions](../composing-actions/), where checkout splits
into smaller actions for stock, payment and the receipt.
