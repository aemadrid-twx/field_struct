---
title: How to declare failures and handle each outcome
description: List the ways an action can fail or skip, then branch on the result at the call site.
sidebar:
  label: Declare and handle outcomes
  order: 7
---

An action ends in one of three outcomes: success, failure or skip. Declare the
failure and skip codes it can end with, and the caller can handle each one by
name.

## 1. Declare the codes

`fails` and `skips` take a code, a default message, and any metadata you like.
The gem stores the metadata and hands it back on the result; your app decides
what it means. Here it's the HTTP status to answer with:

```ruby title="charge_customer.rb" run
CUSTOMERS = { 1 => :ok, 2 => :declined, 3 => :paid }

class ChargeCustomer < Actionable::Action
  fails :not_found,     'no such customer',      http: 404
  fails :card_declined, 'the card was declined', http: 402
  skips :already_paid,  'nothing to charge'

  input  { required :customer_id, :integer }
  output { required :charge_id, :string }

  step :find_customer
  step :charge

  def find_customer
    fail!(:not_found) unless CUSTOMERS.key?(input.customer_id)
    skip!(:already_paid) if CUSTOMERS[input.customer_id] == :paid
  end

  def charge
    fail!(:card_declined) if CUSTOMERS[input.customer_id] == :declined
    @charge_id = "ch_#{input.customer_id}"
  end
end
```

Once an action declares a failure code, it may only fail with declared codes.
A typo like `fail!(:card_declind)` raises `Actionable::DefinitionError` instead
of becoming a new code. `skips` works the same way for skip codes.

## 2. Read the result

Each run returns one result. A failure or skip carries the code, the declared
message (unless the call passed its own) and the declared metadata:

```ruby run
declined = ChargeCustomer.run(customer_id: 2)
declined.status    # => :failure
declined.code      # => :card_declined
declined.message   # => "the card was declined"
declined.metadata  # => { http: 402 }

ChargeCustomer.run(customer_id: 3).status     # => :skipped
ChargeCustomer.run(customer_id: 1).charge_id  # => "ch_1"
```

## 3. Branch at the call site

Each outcome is its own class (`Actionable::Success`, `Actionable::Skipped`,
`Actionable::Failure`), and results support pattern matching on `code`,
`message`, `output` and (for a failure or skip) `metadata`. So one `case`/`in` covers every outcome,
including the gem's own `:invalid_input`. Keep an `else`: a failure without
`http:` metadata (`:invalid_output`, or a code from an action that declares
none) would otherwise raise `NoMatchingPatternError`:

```ruby run
def respond_to_charge(result)
  case result
  in Actionable::Success       then [201, { charge_id: result.charge_id }]
  in Actionable::Skipped       then [200, { note: result.message }]
  in { code: :invalid_input }  then [422, { errors: result.errors.to_h }]
  in { metadata: { http: } }   then [http, { error: result.message }]
  else                              [500, { error: result.message }]
  end
end

respond_to_charge(ChargeCustomer.run(customer_id: 1))      # => [201, { charge_id: "ch_1" }]
respond_to_charge(ChargeCustomer.run(customer_id: 3))      # => [200, { note: "nothing to charge" }]
respond_to_charge(ChargeCustomer.run(customer_id: 'x'))    # => [422, { errors: { customer_id: ["could not be coerced: Integer fields expect a base-10 integer, got a String that is not one"] } }]
respond_to_charge(ChargeCustomer.run(customer_id: 99))     # => [404, { error: "no such customer" }]
```

A skip means "nothing to do": it's not a failure, so `result.ok?` is true for
both a success and a skip.

## See also

- actionable USAGE: [Declared failures](https://github.com/Paymentbox-com/actionable/blob/v1.10.0/USAGE.md#declared-failures), [Declared skips](https://github.com/Paymentbox-com/actionable/blob/v1.10.0/USAGE.md#declared-skips), [Results](https://github.com/Paymentbox-com/actionable/blob/v1.10.0/USAGE.md#results)
- Tutorial: [Placing the order](../../tutorial/placing-the-order/)
