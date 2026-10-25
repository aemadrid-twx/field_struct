---
title: Placing the order
description: "Chapter 3: your first Actionable action, with steps, typed input and output, and a declared failure."
sidebar:
  label: 3. Placing the order
  order: 4
---

You can model an order. Now you need to *place* it: check that the books are in
stock, set the copies aside and confirm. In this chapter you'll write that as an
[Actionable](https://github.com/Paymentbox-com/actionable) action.

An action is a service object. You subclass `Actionable::Action`, list its
steps, write each step as a method, and call `.run`. Every run returns one
result: a success, a failure or a skip.

## Where we left off

This chapter uses the `Book`, `LineItem` and `Order` classes from
[chapter 1](../a-typed-book/) and [chapter 2](../orders-and-json/):

<details>
<summary>The classes from chapters 1 and 2</summary>

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
```

</details>

## Stock to sell

A real store keeps its stock in a database. For this tutorial a Hash of ISBN to
copies on hand will do:

```ruby run
STOCK = { '978-1-68050-981-8' => 3, '978-1-93778-549-9' => 1 }
```

## Write the action

```ruby title="place_order.rb" run
class PlaceOrder < Actionable::Action
  fails :out_of_stock, 'a book in the order is out of stock'

  input { required :order, Order }

  output do
    required :order_number, :string
    required :total,        :decimal
  end

  step :check_stock
  step :reserve_copies
  step :confirm

  def check_stock
    input.order.lines.each do |line|
      left = STOCK.fetch(line.book.isbn, 0)
      fail!(:out_of_stock, "only #{left} left of #{line.book.title}") if left < line.quantity
    end
  end

  def reserve_copies
    input.order.lines.each { |line| STOCK[line.book.isbn] -= line.quantity }
  end

  def confirm
    @order_number = input.order.number
    @total        = input.order.total
    succeed("Order #{@order_number} placed")
  end
end
```

Here's what each part does:

- **`fails :out_of_stock, '…'`** declares a way this action can fail, with a
  default message. Once an action declares a failure code, it can only fail with
  declared codes; any other code raises `Actionable::DefinitionError`, so typos
  surface right away.
- **`input { … }`** declares the arguments `.run` takes, with the same DSL as a
  FieldStruct. Here it takes one `Order`.
- **`output { … }`** declares what a success returns. At the end of the run,
  instance variables named after output fields (`@order_number`, `@total`) are
  collected and coerced into the output.
- **`step`** lists the steps in the order they run. Each one is a method.
- **`fail!`** records a failure and stops: no later step runs. `succeed` records
  a success with a message.

:::note
Bang verbs (`fail!`, `succeed!`, `skip!`) stop the run. Plain ones (`fail`,
`succeed`, `skip`) record an outcome and let the next steps run, so a plain verb
must be the last expression in its method. `succeed` in `confirm` is. See
[Control flow](https://github.com/Paymentbox-com/actionable/blob/v1.8.2/USAGE.md#control-flow).
:::

## Run it

Pass the input as keyword arguments to `.run`:

```ruby run
order = Order.new(
  number: 'A-1001',
  email: 'ann@example.com',
  lines: [
    { book: { isbn: '978-1-68050-981-8', title: 'Eloquent Ruby', price: '24.99' }, quantity: 2 },
    { book: { isbn: '978-1-93778-549-9', title: 'Practical Object-Oriented Design', price: '39.95' }, quantity: 1 }
  ]
)

result = PlaceOrder.run(order: order)
result.success?       # => true
result.failure?       # => false
result.status         # => :success
result.message        # => "Order A-1001 placed"
result.output.total   # => BigDecimal('89.93')
result.order_number   # => "A-1001"
```

Output fields are on `result.output`, and also directly on the result as a
shortcut: `result.order_number` is `result.output.order_number`.

The steps really ran, so the copies are reserved:

```ruby run
STOCK  # => { '978-1-68050-981-8' => 1, '978-1-93778-549-9' => 0 }
```

## A declared failure

Place the same order again. There's one copy of *Eloquent Ruby* left, and the
order wants two:

```ruby run
again = PlaceOrder.run(order: order)
again.success?   # => false
again.failure?   # => true
again.code       # => :out_of_stock
again.message    # => "only 1 left of Eloquent Ruby"
STOCK            # => { '978-1-68050-981-8' => 1, '978-1-93778-549-9' => 0 }
```

`fail!` stopped the run in `check_stock`, so `reserve_copies` never ran and the
stock didn't change.

`code` is what your code branches on; `message` is for people. The message
passed to `fail!` replaced the default from `fails`. Call `fail!(:out_of_stock)`
with no message and the result carries the default, `"a book in the order is out
of stock"`.

Don't rely on `output` after a failure. Actionable only validates the output of a
success.

## Bad input never reaches your steps

If the input doesn't match the `input` block, the action fails with the code
`:invalid_input` before the first step runs. `errors` says what was wrong:

```ruby run
missing = PlaceOrder.run
missing.code             # => :invalid_input
missing.errors[:order]   # => ["is required"]

broken = PlaceOrder.run(order: { number: 'A-1002', email: 'not-an-email', lines: [] })
broken.code              # => :invalid_input
broken.errors[:order]    # => ["is invalid"]
```

`:invalid_input` is one of the codes Actionable produces itself, so you don't
have to declare it with `fails`. The input coerces hashes just like a struct, so
`broken` was built into an `Order`, found invalid, and stopped there.

## Branch on the result

In a controller or a job, check the outcome and act on it:

```ruby run
def checkout_message(result)
  if result.success?
    "Thanks! Your total is $#{result.total.to_s('F')}."
  elsif result.code == :out_of_stock
    "Sorry, #{result.message}."
  else
    "Please check your order: #{result.errors.full_messages.join(', ')}"
  end
end

STOCK['978-1-68050-981-8'] = 5
STOCK['978-1-93778-549-9'] = 5
checkout_message(PlaceOrder.run(order: order))  # => "Thanks! Your total is $89.93."
checkout_message(PlaceOrder.run)                # => "Please check your order: Order is required"
```

## What you built

A `PlaceOrder` action that:

- takes a typed `Order` as input and rejects bad input before any step runs,
- runs three steps in order and stops early with a declared `:out_of_stock` failure,
- returns a typed output (`order_number`, `total`) on success,
- gives the caller one result to branch on with `success?`, `failure?`, `code` and `message`.

Actions can do much more: skips for "nothing to do", lifecycle hooks, nested
actions, batches and more. The actionable
[getting started guide](https://github.com/Paymentbox-com/actionable/blob/v1.8.2/docs/getting_started.md)
and [USAGE reference](https://github.com/Paymentbox-com/actionable/blob/v1.8.2/USAGE.md)
cover them.

**Next:** more chapters are on the way. Until then, the
[how-to guides](../../how-to/) point to recipes for specific tasks.
