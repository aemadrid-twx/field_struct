---
title: How to test structs and actions with RSpec
description: Assert an action's outcome with one matcher, stub a collaborator action, and spec a struct's validation.
sidebar:
  label: Test with RSpec
  order: 11
---

Actionable ships a matcher and stub helpers for RSpec. Load them in
`spec/spec_helper.rb`, after RSpec:

```ruby run
require 'rspec'
require 'actionable/rspec'
```

The code under test in this guide:

```ruby title="app code" run
class Price < FieldStruct::Base
  required :cents, :integer, in: (0..)
end

class Charge < Actionable::Action
  fails :invalid_amount, 'amount must be positive'

  input  { required :amount, :integer }
  output { required :charged, :integer }

  step :charge

  def charge
    fail!(:invalid_amount) unless input.amount.positive?
    @charged = input.amount
    succeed("charged #{input.amount}")
  end
end

class Checkout < Actionable::Action
  fails :invalid_amount

  input  { required :amount, :integer }
  output { required :charged, :integer }

  step :prepare
  step Charge, input: %i[amount]

  def prepare = @amount = input.amount
end
```

## Spec a struct

A struct needs no helpers: build it and check `valid?` and `errors`:

```ruby title="spec/price_spec.rb" run
RSpec.describe Price do
  it('coerces a numeric string') { expect(Price.new(cents: '250').cents).to eq(250) }
  it('rejects a negative amount') { expect(Price.new(cents: -1).errors[:cents]).to eq(['is invalid']) }
end
```

## Assert an action's outcome

`perform_actionable(...)` runs the action with those arguments. Chain
`and_succeed`, `and_fail(code)`, `and_skip(code)` or `and_raise(ErrorClass)`;
a message argument is matched with `===`, so a Regexp works. A block gets
`(result, exception)` for anything else you want to check, and must return a
truthy value for the spec to pass:

```ruby title="spec/charge_spec.rb" run
RSpec.describe Charge do
  it 'charges a positive amount' do
    expect(Charge).to perform_actionable(amount: 10).and_succeed('charged 10')
  end

  it 'refuses a negative amount' do
    expect(Charge).to perform_actionable(amount: -5).and_fail(:invalid_amount, /positive/)
  end

  it 'rejects bad input' do
    expect(Charge).to perform_actionable(amount: 'ten').and_fail(:invalid_input)
  end

  it 'returns what it charged' do
    expect(Charge).to perform_actionable(amount: 10).and_succeed { |result, _error| result.charged == 10 }
  end
end
```

On an action that declares failures, `and_fail` with an undeclared code raises
`ArgumentError`: the spec would test a failure the action can never return.

## Stub a collaborator action

To test `Checkout` without running `Charge`, stub `Charge.run` to return a real
result. `allow_actionable_*` permits the call; `stub_actionable_*` also expects
it:

```ruby title="spec/checkout_spec.rb" run
RSpec.describe Checkout do
  it 'passes the charge on' do
    stub_actionable_success(Charge, output: { charged: 99 })
    expect(Checkout.run(amount: 10).charged).to eq(99)
  end

  it 'fails when the charge fails' do
    allow_actionable_failure(Charge, code: :invalid_amount)
    expect(Checkout).to perform_actionable(amount: 10).and_fail(:invalid_amount, 'amount must be positive')
  end
end
```

The stubbed failure got its message from `Charge`'s `fails` declaration.

## Run them

In a project you run `bundle exec rspec`. This page runs the specs above
in-process, and checks that all of them pass:

```ruby run
RSpec::Core::Runner.run([])  # => 0
```

## See also

- actionable USAGE: [RSpec integration](https://github.com/Paymentbox-com/actionable/blob/v1.9.0/USAGE.md#rspec-integration), [Outcome coverage](https://github.com/Paymentbox-com/actionable/blob/v1.9.0/USAGE.md#outcome-coverage) (find the declared outcomes no spec reaches)
