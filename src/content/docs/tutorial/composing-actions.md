---
title: Composing actions
description: "Chapter 5: split checkout into small actions, run them as steps of one parent, and see how a child's failure or skip reaches the parent."
sidebar:
  label: 5. Composing actions
  order: 6
---

A real checkout does more than count stock. It charges a card and emails a
receipt too. You could keep adding steps to `PlaceOrder`, but each of those jobs
is useful on its own: a refund also touches stock, and an admin may resend a
receipt. In this chapter you'll write each job as its own small action, then
compose them into one `Checkout`.

## Where we left off

This chapter starts from the `Book`, `LineItem` and `Order` classes and the
`STOCK` hash from [chapter 3](../placing-the-order/):

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

## Three small actions

First, stock. `ReserveStock` is chapter 3's `check_stock` and `reserve_copies`
steps in an action of their own. Its output, `reserved`, lists the line items it
set aside:

```ruby title="reserve_stock.rb" run
class ReserveStock < Actionable::Action
  fails :out_of_stock, 'a book in the order is out of stock'

  input  { required :order, Order }
  output { required :reserved, :array, of: LineItem }

  step :check_stock
  step :reserve_copies

  def check_stock
    input.order.lines.each do |line|
      left = STOCK.fetch(line.book.isbn, 0)
      fail!(:out_of_stock, "only #{left} left of #{line.book.title}") if left < line.quantity
    end
  end

  def reserve_copies
    @reserved = input.order.lines
    @reserved.each { |line| STOCK[line.book.isbn] -= line.quantity }
  end
end
```

Next, the payment. There's no real payment gateway here: `CHARGES` records each
charge, and the test token `tok_declined` is always declined. An order that
costs nothing has nothing to charge, so that's a skip:

```ruby title="charge_payment.rb" run
CHARGES = []

class ChargePayment < Actionable::Action
  fails :card_declined, 'the card was declined'
  skips :nothing_to_charge

  input  { required :order, Order }
  output { required :charge_id, :string }

  step :charge

  def charge
    skip!(:nothing_to_charge) if input.order.total.zero?
    fail!(:card_declined) if input.order.payment_token == 'tok_declined'

    @charge_id = "ch_#{CHARGES.size + 1}"
    CHARGES << { id: @charge_id, amount: input.order.total }
  end
end
```

Last, the receipt. `OUTBOX` stands in for your mailer. A free order has no
charge, so `charge_id` is optional:

```ruby title="send_receipt.rb" run
OUTBOX = []

class SendReceipt < Actionable::Action
  input do
    required :order,     Order
    optional :charge_id, :string
  end

  step :deliver

  def deliver
    OUTBOX << { to: input.order.email, order: input.order.number, charge: input.charge_id }
  end
end
```

Each one is a normal action you can run, and test, by itself:

```ruby run
order = Order.new(
  number: 'A-1001',
  email: 'ann@example.com',
  payment_token: 'tok_visa',
  lines: [{ book: { isbn: '978-1-68050-981-8', title: 'Eloquent Ruby', price: '24.99' }, quantity: 1 }]
)

ChargePayment.run(order: order).charge_id   # => "ch_1"
CHARGES                                     # => [{ id: "ch_1", amount: BigDecimal('24.99') }]
```

That was just a demo, so clear the charge before you go on:

```ruby run
CHARGES.clear
```

## Compose them

To run an action as a step of another, pass its class to `step` instead of a
method name:

```ruby title="checkout.rb" run
class Checkout < Actionable::Action
  fails :out_of_stock,  'a book in the order is out of stock'
  fails :card_declined, 'the card was declined'

  input { required :order, Order }

  output do
    required :order_number, :string
    optional :charge_id,    :string
  end

  step :prepare
  step ReserveStock,  input: %i[order]
  step ChargePayment, input: %i[order]
  step SendReceipt,   input: %i[order charge_id]
  step :confirm

  def prepare
    @order = input.order
  end

  def confirm
    @order_number = @order.number
    succeed("Order #{@order_number} placed")
  end
end
```

Data moves between parent and children through instance variables:

- **`input: %i[order]`** names the parent's instance variables to pass to the
  child's `.run`. `step ReserveStock, input: %i[order]` calls
  `ReserveStock.run(order: @order)`. That's why `prepare` copies `input.order`
  into `@order` first.
- **The child's output comes back** as instance variables on the parent. After
  `ChargePayment` succeeds, the parent has `@charge_id`, which it passes on to
  `SendReceipt` and which ends up in its own output. `ReserveStock` likewise
  sets `@reserved`. Only fields the child actually set come back.
- **`expose:`** limits what comes back, for example
  `step ChargePayment, input: %i[order], expose: %i[charge_id]`. Without it the
  parent gets every output field the child set.

Check out an order for two books:

```ruby run
order = Order.new(
  number: 'A-1001',
  email: 'ann@example.com',
  payment_token: 'tok_visa',
  lines: [
    { book: { isbn: '978-1-68050-981-8', title: 'Eloquent Ruby', price: '24.99' }, quantity: 2 },
    { book: { isbn: '978-1-93778-549-9', title: 'Practical Object-Oriented Design', price: '39.95' }, quantity: 1 }
  ]
)

result = Checkout.run(order: order)
result.success?       # => true
result.message        # => "Order A-1001 placed"
result.charge_id      # => "ch_1"
STOCK                 # => { '978-1-68050-981-8' => 1, '978-1-93778-549-9' => 0 }
CHARGES               # => [{ id: "ch_1", amount: BigDecimal('89.93') }]
OUTBOX                # => [{ to: "ann@example.com", order: "A-1001", charge: "ch_1" }]
```

## A child's failure is the parent's failure

When a child fails, the parent fails with the child's code, message and errors,
and no later step runs. The caller sees one result and doesn't need to know
which child said no:

```ruby run
STOCK['978-1-68050-981-8'] = 5
STOCK['978-1-93778-549-9'] = 5

declined = Order.new(
  number: 'A-1002',
  email: 'bo@example.com',
  payment_token: 'tok_declined',
  lines: [{ book: { isbn: '978-1-68050-981-8', title: 'Eloquent Ruby', price: '24.99' }, quantity: 2 }]
)

failed = Checkout.run(order: declined)
failed.code      # => :card_declined
failed.message   # => "the card was declined"
OUTBOX.size      # => 1
```

`SendReceipt` never ran for `A-1002`, so the outbox still holds only the first
receipt. Because the failure became `Checkout`'s own, the `case`/`in` handler
from [chapter 4](../when-things-go-wrong/) works on it unchanged.

That's also why `Checkout` declares `:out_of_stock` and `:card_declined`. An
action that declares failures may only fail with codes it declares, and a
child's codes become its own. Leave one out and the run raises
`Actionable::DefinitionError` the first time that child fails:

```ruby run
class ForgetfulCheckout < Actionable::Action
  fails :out_of_stock

  input { required :order, Order }

  step :prepare
  step ChargePayment, input: %i[order]

  def prepare
    @order = input.order
  end
end

error = begin
  ForgetfulCheckout.run(order: declined)
rescue Actionable::DefinitionError => e
  e
end
error.class   # => Actionable::DefinitionError
```

## Undo with an `on_failure` hook

Look at the stock after that declined card:

```ruby run
STOCK   # => { '978-1-68050-981-8' => 3, '978-1-93778-549-9' => 5 }
```

`ReserveStock` set aside two copies, then `ChargePayment` failed, and nobody
put them back. A **lifecycle hook** fixes that. `on_failure` names a method
that runs after the steps, only when the run ends in a failure. Add it to
`Checkout`:

```ruby run
class Checkout
  on_failure :release_copies

  def release_copies
    @reserved&.each { |line| STOCK[line.book.isbn] += line.quantity }
  end
end
```

Here the class is reopened to add the hook; in `checkout.rb` you'd write
these lines inside the class. `@reserved` is `ReserveStock`'s output, so it's
only set if the reservation happened. When `ReserveStock` itself fails, there's
nothing to release and `&.` skips the loop.

Try the declined card again:

```ruby run
STOCK['978-1-68050-981-8'] = 5

again = Checkout.run(order: declined)
again.code   # => :card_declined
STOCK        # => { '978-1-68050-981-8' => 5, '978-1-93778-549-9' => 5 }
```

The copies were reserved and released in the same run. There are also
`on_success`, `on_skip` and `always` (runs after the outcome hook, whatever the
outcome). A hook only runs when the run gets to the end. An exception skips it,
like any other code after a `raise`.

## A child's skip doesn't stop the parent

A skip means "nothing to do here", not "stop". When a child skips, the parent
carries on as if it had succeeded. A free ebook has nothing to charge:

```ruby run
free = Order.new(
  number: 'A-1003',
  email: 'cy@example.com',
  lines: [{ book: { isbn: '978-1-93778-549-9', title: 'Practical Object-Oriented Design', price: '0', format: 'ebook' }, quantity: 1 }]
)

gift = Checkout.run(order: free)
gift.success?    # => true
gift.charge_id   # => nil
OUTBOX.last      # => { to: "cy@example.com", order: "A-1003", charge: nil }
```

`ChargePayment` skipped, so it set no `charge_id`, and `SendReceipt` ran
without one. The child's skip never becomes the parent's outcome, so
`Checkout` doesn't declare `:nothing_to_charge`.

## See what ran

To check which steps ran, and how long each took, turn on measurement with
`measure :all`. The result's `history` then lists every step:

```ruby run
class Checkout
  measure :all
end

STOCK['978-1-68050-981-8'] = 5
STOCK['978-1-93778-549-9'] = 5

paid = Checkout.run(order: Order.new(number: 'A-1004', email: 'di@example.com', payment_token: 'tok_visa', lines: order.lines))
paid.history.steps.map(&:name)   # => [:prepare, ReserveStock, ChargePayment, SendReceipt, :confirm]
paid.history.steps[1].nested.steps.map(&:name)   # => [:check_stock, :reserve_copies]

lost = Checkout.run(order: declined)
lost.history.steps.map(&:name)      # => [:prepare, ReserveStock, ChargePayment, :release_copies]
lost.history.steps.map(&:section)   # => [:main, :main, :main, :failure]
```

- A nested action's own steps are under `nested`.
- On the failure, the history stops at `ChargePayment` and then shows the
  `release_copies` hook, in the `:failure` section.
- Each step also has a `duration` in seconds, and `history.took` adds them up.

`measure :none` is the default and records nothing. `measure :sampled, rate: 0.1`
measures about one run in ten, which keeps the cost low in production.

## What you built

- Three small actions, `ReserveStock`, `ChargePayment` and `SendReceipt`, each
  runnable and testable alone.
- A `Checkout` that runs them as steps, passing data in with `input:` and
  getting output back as instance variables.
- A failure in any child that ends the whole checkout with the child's code,
  plus an `on_failure` hook that puts reserved stock back.
- A child skip that lets the checkout carry on.
- A step-by-step history of each run.

More in the actionable USAGE reference:
[Nested actions](https://github.com/Paymentbox-com/actionable/blob/v1.9.0/USAGE.md#nested-actions),
[Lifecycle hooks](https://github.com/Paymentbox-com/actionable/blob/v1.9.0/USAGE.md#lifecycle-hooks)
and [History & measurement](https://github.com/Paymentbox-com/actionable/blob/v1.9.0/USAGE.md#history--measurement).

**Next:** [Into an app](../into-an-app/), where `Checkout` gets a controller, a
background job and specs.
