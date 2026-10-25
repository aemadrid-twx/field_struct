---
title: Into an app
description: "Chapter 6: call the checkout from a controller, run it in an ActiveJob background job with retries, and test it with Actionable's RSpec helpers."
sidebar:
  label: 6. Into an app
  order: 7
---

`Checkout` works in a script. Now it needs to live in an app: a JSON endpoint
that places orders, a background job for when the payment gateway is slow, and
specs. This chapter uses Rails' conventions, but the only extra gems it needs
are ActiveJob and RSpec, so every example still runs on its own. To follow
along, add `gem 'activejob'` and `gem 'rspec'` to your `Gemfile` (the examples
are checked against ActiveJob 8 and RSpec 3.13).

## Where we left off

This chapter uses the structs from chapters 1 and 2, and `ReserveStock` and
`SendReceipt` from [chapter 5](../composing-actions/):

<details>
<summary>The code from chapters 1 to 5</summary>

```ruby title="app/models/order.rb" run
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

```ruby title="app/actions/reserve_stock.rb" run
STOCK = { '978-1-68050-981-8' => 3, '978-1-93778-549-9' => 1 }

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

```ruby title="app/actions/send_receipt.rb" run
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

</details>

## A gateway that times out

Real payment gateways sometimes time out. That's not the customer's fault, and
trying again a little later usually works. `ChargePayment` gets a new declared
failure for it. The test token `tok_timeout` stands in for a slow gateway:

```ruby title="app/actions/charge_payment.rb" run ins={5,14}
CHARGES = []

class ChargePayment < Actionable::Action
  fails :card_declined,   'the card was declined'
  fails :gateway_timeout, 'the payment gateway timed out'
  skips :nothing_to_charge

  input  { required :order, Order }
  output { required :charge_id, :string }

  step :charge

  def charge
    fail!(:gateway_timeout) if input.order.payment_token == 'tok_timeout'
    skip!(:nothing_to_charge) if input.order.total.zero?
    fail!(:card_declined) if input.order.payment_token == 'tok_declined'

    @charge_id = "ch_#{CHARGES.size + 1}"
    CHARGES << { id: @charge_id, amount: input.order.total }
  end
end
```

`Checkout` declares the new code too, since a child's failure becomes its own.
Each failure also gets an `http_status` in its metadata, as in
[chapter 4](../when-things-go-wrong/#errors-as-data), and the
`on_failure` hook from chapter 5 moves into the class:

```ruby title="app/actions/checkout.rb" run ins={2-5,20,31-33}
class Checkout < Actionable::Action
  fails :out_of_stock,    'a book in the order is out of stock', http_status: 409
  fails :card_declined,   'the card was declined', http_status: 402
  fails :gateway_timeout, 'the payment gateway timed out', http_status: 503
  fails :invalid_input,   http_status: 422

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

  on_failure :release_copies

  def prepare
    @order = input.order
  end

  def confirm
    @order_number = @order.number
    succeed("Order #{@order_number} placed")
  end

  def release_copies
    @reserved&.each { |line| STOCK[line.book.isbn] += line.quantity }
  end
end
```

## A JSON endpoint

The browser posts the order as JSON, with the camelCase keys you set up in
[chapter 2](../orders-and-json/#use-the-json-keys-your-api-expects).
`Order.from_json` turns it into an `Order`, the controller runs `Checkout`, and
`case`/`in` turns the result into a response.

So that this page runs without Rails, a tiny `ApplicationController` stands in
for `ActionController::API`. Like Rails, it gives you `request.body` as an IO,
and it records what `render` was called with:

```ruby title="stand-in for Rails" run
require 'stringio'

class ApplicationController
  Request = Struct.new(:body)

  attr_reader :request, :response

  def initialize(request_body)
    @request = Request.new(StringIO.new(request_body))
  end

  def render(json:, status:)
    @response = { status: status, json: json }
  end
end
```

The controller is what you'd write in a Rails app:

```ruby title="app/controllers/orders_controller.rb" run
class OrdersController < ApplicationController
  def create
    result = Checkout.run(order: Order.from_json(request.body.read))

    case result
    in Actionable::Success(output: { order_number:, charge_id: })
      render json: { orderNumber: order_number, chargeId: charge_id }, status: 201
    in Actionable::Failure(code:, message:)
      render json: { error: code, message: message, details: result.errors.to_h },
             status: result.metadata.fetch(:http_status, 500)
    end
  end
end
```

Two branches are enough. `Checkout` declares no skips, and a child's skip never
becomes the parent's outcome, so a `Checkout` result is always a success or a
failure. If that ever changes, `case`/`in` raises `NoMatchingPatternError`
rather than sending a wrong response.

Post a few orders:

```ruby run
def post_order(token, quantity: 1, email: 'ann@example.com', number: 'A-1001')
  body = %({"orderNumber":"#{number}","email":"#{email}","paymentToken":"#{token}",) +
         %("lines":[{"book":{"isbn":"978-1-68050-981-8","title":"Eloquent Ruby","price":"24.99"},"quantity":#{quantity}}]})
  controller = OrdersController.new(body)
  controller.create
  controller.response
end

post_order('tok_visa')                     # => { status: 201, json: { orderNumber: "A-1001", chargeId: "ch_1" } }
post_order('tok_declined', number: 'A-1002')[:status]   # => 402
post_order('tok_visa', quantity: 9, number: 'A-1003')   # => { status: 409, json: { error: :out_of_stock, message: "only 2 left of Eloquent Ruby", details: {} } }
post_order('tok_visa', email: 'nope')                    # => { status: 422, json: { error: :invalid_input, message: "input failed validation", details: { order: ["is invalid"] } } }
STOCK['978-1-68050-981-8']                               # => 2
```

The declined card put its copy back (the `on_failure` hook), so only the first
order's copy is gone. A body that isn't JSON at all makes `from_json` raise
before `Checkout` runs, and your app's usual error handling takes over, as for
any other exception.

## A background job

A checkout that waits on a payment gateway can be slow. Many apps take the
order, answer right away and do the work in a background job. Actionable's job
adapter maps a result to what the queue should do with it:

- **ack:** a success or a skip. The job is done.
- **discard:** a failure that won't get better by trying again. The job
  returns normally and isn't retried.
- **retry:** any other failure. The job raises
  `Actionable::Job::RetryableFailure`, so the queue tries it again later.

Which failures are permanent is up to you. The default list is `:invalid_input`,
`:invalid_output` and `:not_found`. For a checkout, a declined card or a sold-out
book won't change on a retry, but a gateway timeout might:

```ruby title="app/jobs/checkout_job.rb" run
require 'active_job'
require 'actionable/job'

class CheckoutJob < ActiveJob::Base
  include Actionable::Job::Mixin

  retry_on Actionable::Job::RetryableFailure, wait: 30, attempts: 5

  def perform(order_json)
    run_actionable(Checkout, order: Order.from_json(order_json))
  end

  def actionable_permanent_codes = Actionable::Job::DEFAULT_PERMANENT_CODES + %i[out_of_stock card_declined]
end
```

- `include Actionable::Job::Mixin` adds `run_actionable`, which runs the action
  and raises `RetryableFailure` for a failure that should be retried.
- `retry_on` is ActiveJob's own: when the job raises that error, it's enqueued
  again in 30 seconds, up to 5 attempts in all.
- The mixin isn't tied to ActiveJob. It works the same in a Sidekiq job.

To watch the queue, use ActiveJob's test adapter, which keeps enqueued jobs in a
list instead of running them:

```ruby run
STOCK['978-1-93778-549-9'] = 10 # a fresh delivery
ActiveJob::Base.queue_adapter = :test
ActiveJob::Base.logger = Logger.new(nil) # keep the example output quiet
queue = ActiveJob::Base.queue_adapter.enqueued_jobs

def order_json(token, number)
  Order.new(number: number, email: 'bo@example.com', payment_token: token,
            lines: [{ book: { isbn: '978-1-93778-549-9', title: 'Practical Object-Oriented Design', price: '39.95' }, quantity: 1 }]).to_json
end

CheckoutJob.perform_later(order_json('tok_visa', 'B-1'))
queue.size                                         # => 1
queue.first['arguments'].first.include?('B-1')     # => true
queue.clear
```

`perform_later` only enqueues. The job's argument is the order's JSON, a plain
String, which every queue backend can store.

Now run each kind of outcome with `perform_now`, which runs the job right away:

```ruby run
CheckoutJob.perform_now(order_json('tok_declined', 'B-2'))
queue.size         # => 0

CheckoutJob.perform_now(order_json('tok_timeout', 'B-3'))
queue.size         # => 1
queue.first['arguments'].first.include?('B-3')   # => true

queue.clear
CheckoutJob.perform_now(order_json('tok_visa', 'B-4'))
queue.size         # => 0
OUTBOX.last[:order]   # => "B-4"
```

The declined card was discarded and the timeout was put back on the queue.
The order that went through was acknowledged. To check a disposition without a
job, ask `Actionable::Job.disposition`:

```ruby run
declined = Checkout.run(order: Order.from_json(order_json('tok_declined', 'B-5')))
declined.code                                                        # => :card_declined
Actionable::Job.disposition(declined)                                # => :retry
Actionable::Job.disposition(declined, permanent: %i[card_declined])  # => :discard
```

Without the job's own list, a declined card would be retried too. That's why
`CheckoutJob` overrides `actionable_permanent_codes`.

## Specs

Actionable ships an RSpec matcher and stub helpers. In `spec/spec_helper.rb`,
load them after RSpec. (The specs below reuse the `order_json` helper from the
job section; in your app, put it in `spec/support/`.)

```ruby title="spec/spec_helper.rb" run
require 'rspec'
require 'actionable/rspec'
```

`perform_actionable(...)` runs the action with those arguments, then checks the
outcome with `and_succeed`, `and_fail(code)` or `and_skip(code)`. A message
argument is matched with `===`, so a Regexp works too:

```ruby title="spec/actions/checkout_spec.rb" run
RSpec.describe Checkout do
  let(:order) do
    Order.new(number: 'S-1', email: 'ann@example.com', payment_token: 'tok_visa',
              lines: [{ book: { isbn: '978-1-93778-549-9', title: 'POODR', price: '39.95' }, quantity: 1 }])
  end

  before { STOCK['978-1-93778-549-9'] = 1 }

  it 'places the order' do
    expect(Checkout).to perform_actionable(order: order).and_succeed('Order S-1 placed')
  end

  it 'fails when a book is sold out' do
    STOCK['978-1-93778-549-9'] = 0
    expect(Checkout).to perform_actionable(order: order).and_fail(:out_of_stock, /only 0 left/)
  end

  it 'puts the stock back when the card is declined' do
    allow_actionable_failure(ChargePayment, code: :card_declined)

    expect(Checkout).to perform_actionable(order: order).and_fail(:card_declined, 'the card was declined')
    expect(STOCK['978-1-93778-549-9']).to eq(1)
  end
end
```

`allow_actionable_failure(ChargePayment, code: :card_declined)` makes
`ChargePayment.run` return a real failure without running it. That's how you
test the parent's handling of a child's failure without a real gateway. The
stubbed failure took its message from `ChargePayment`'s `fails` declaration.
A stub with a code the action doesn't declare raises `ArgumentError`, since
the action could never return it.

The same helpers work one level up. To spec the job and the controller, stub
`Checkout` itself:

```ruby title="spec/jobs/checkout_job_spec.rb" run
RSpec.describe CheckoutJob do
  let(:queue) { ActiveJob::Base.queue_adapter.enqueued_jobs }

  before { queue.clear }

  it 'retries a gateway timeout' do
    allow_actionable_failure(Checkout, code: :gateway_timeout)
    expect { CheckoutJob.perform_now(order_json('tok_visa', 'S-2')) }.to change(queue, :size).by(1)
  end

  it 'gives up on a declined card' do
    allow_actionable_failure(Checkout, code: :card_declined)
    expect { CheckoutJob.perform_now(order_json('tok_visa', 'S-3')) }.not_to change(queue, :size)
  end
end

RSpec.describe OrdersController do
  it 'answers 503 when the gateway times out' do
    allow_actionable_failure(Checkout, code: :gateway_timeout)
    controller = OrdersController.new(order_json('tok_visa', 'S-4'))
    controller.create
    expect(controller.response[:status]).to eq(503)
  end
end
```

The stubbed failures carry `Checkout`'s declared metadata, so the controller
spec gets its `503` from the same `http_status` the real failure would.

In a project you run `bundle exec rspec`. This page runs the specs in-process
and checks that they all pass:

```ruby run
RSpec::Core::Runner.run([])  # => 0
```

## What you built

- An `OrdersController#create` that turns JSON into an `Order`, runs
  `Checkout` and maps each result to a response, with the HTTP status read from
  the failure's metadata.
- A `CheckoutJob` on ActiveJob that acknowledges a success, discards failures a
  retry can't fix and retries a gateway timeout.
- Specs that run `Checkout` with `perform_actionable`, and stub a child action,
  or `Checkout` itself, with `allow_actionable_failure`.

That's the end of the tutorial. You've gone from one typed `Book` to a checkout
that's composed, tested and running in the background. From here:

- The actionable [USAGE reference](https://github.com/Paymentbox-com/actionable/blob/v1.9.0/USAGE.md)
  covers what this tutorial skipped: ActiveRecord transactions and
  `after_commit` in the
  [Rails adapter](https://github.com/Paymentbox-com/actionable/blob/v1.9.0/USAGE.md#rails-adapter),
  [batch runs](https://github.com/Paymentbox-com/actionable/blob/v1.9.0/USAGE.md#batch-runs),
  [typed outcomes](https://github.com/Paymentbox-com/actionable/blob/v1.9.0/USAGE.md#typed-outcomes)
  and [outcome coverage](https://github.com/Paymentbox-com/actionable/blob/v1.9.0/USAGE.md#outcome-coverage).
- The field_struct [USAGE reference](https://github.com/Paymentbox-com/field_struct/blob/v0.15.0/USAGE.md)
  lists every type and option.
- The [how-to guides](../../how-to/) have recipes for specific tasks.
