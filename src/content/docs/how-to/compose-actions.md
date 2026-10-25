---
title: How to call one action from another
description: Use an action as a step of another, pass values in, take its outputs back, and let its failures stop the parent.
sidebar:
  label: Compose actions
  order: 8
---

A step can be another action. The parent passes it instance variables as
input, takes its outputs back as instance variables, and stops if it fails.

## 1. Write the child action

```ruby title="charge_card.rb" run
class ChargeCard < Actionable::Action
  fails :card_declined, 'the card was declined', http: 402

  input  { required :amount_cents, :integer }
  output { required :charge_id, :string }

  step :charge

  def charge
    fail!(:card_declined) if input.amount_cents > 10_000
    @charge_id = "ch_#{input.amount_cents}"
  end
end
```

## 2. Use it as a step

`input:` names the parent's instance variables to pass to the child's `.run`.
`expose:` names the child outputs to copy back into the parent (default: all of
them):

```ruby title="checkout.rb" run
class Checkout < Actionable::Action
  fails :card_declined # a child's failure becomes the parent's, so declare it

  input  { required :total_cents, :integer }
  output do
    required :charge_id, :string
    required :receipt,   :string
  end

  step :prepare
  step ChargeCard, input: %i[amount_cents], expose: %i[charge_id]
  step :write_receipt

  def prepare       = @amount_cents = input.total_cents
  def write_receipt = @receipt = "Paid with #{@charge_id}"
end

result = Checkout.run(total_cents: 2_500)
result.charge_id  # => "ch_2500"
result.receipt    # => "Paid with ch_2500"
```

## 3. Let a child failure stop the parent

When the child fails, the parent fails with the child's code, message, errors
and metadata, and its later steps don't run:

```ruby run
declined = Checkout.run(total_cents: 50_000)
declined.code      # => :card_declined
declined.message   # => "the card was declined"
declined.metadata  # => { http: 402 }
```

The parent re-declared `:card_declined` without metadata; the child's
declaration filled it in. If a parent that declares failures leaves out a code
its child can fail with, that failure raises `Actionable::DefinitionError`.

A child that **skips** doesn't stop the parent: the parent carries on as if the
child had succeeded.

## See also

- actionable USAGE: [Nested actions](https://github.com/Paymentbox-com/actionable/blob/v1.9.0/USAGE.md#nested-actions), [Case steps](https://github.com/Paymentbox-com/actionable/blob/v1.9.0/USAGE.md#case-steps) (a branch target can be an action too)
