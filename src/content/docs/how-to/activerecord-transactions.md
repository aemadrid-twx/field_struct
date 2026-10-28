---
title: How to run an action in a database transaction
description: Roll back an action's writes when it fails, and send emails or webhooks only after the commit.
sidebar:
  label: Use ActiveRecord transactions
  order: 10
---

You want an action's writes undone when it fails, and its emails sent only
once the data is really saved. The Rails adapter adds two class macros for
that: `transactional`, which wraps a run in a transaction, and `after_commit`,
for side effects that must wait for the commit. Load it once, for example in
an initializer:

```ruby
require 'actionable/rails'
```

The examples below use an in-memory SQLite database so they can run here:

```ruby title="setup.rb" run
require 'active_record'
require 'actionable/rails'

ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table(:accounts) { |t| t.integer :balance, null: false, default: 0 }
end

class Account < ActiveRecord::Base; end

ann = Account.create!(balance: 100)
bob = Account.create!(balance: 0)
```

## 1. Make the action transactional

`transactional model:` takes the model whose `transaction` to use (a class, or
a symbol like `:account`). A success commits. A failure or a raised exception
rolls back:

```ruby title="transfer.rb" run
NOTIFICATIONS = []

class Transfer < Actionable::Action
  transactional model: Account
  fails :insufficient_funds, 'not enough money'

  input do
    required :from_id, :integer
    required :to_id,   :integer
    required :amount,  :integer, in: (1..)
  end

  step :credit
  step :debit
  after_commit :notify

  def credit = Account.find(input.to_id).increment!(:balance, input.amount)

  def debit
    from = Account.find(input.from_id)
    fail!(:insufficient_funds) if from.balance < input.amount
    from.decrement!(:balance, input.amount)
  end

  def notify = NOTIFICATIONS << "moved #{input.amount}"
end
```

`credit` runs before `debit` on purpose, to show the rollback: when `debit`
fails, the credit is undone.

```ruby run
Transfer.run(from_id: ann.id, to_id: bob.id, amount: 30).success?  # => true
[ann.reload.balance, bob.reload.balance]                           # => [70, 30]

Transfer.run(from_id: ann.id, to_id: bob.id, amount: 500).code     # => :insufficient_funds
[ann.reload.balance, bob.reload.balance]                           # => [70, 30]
```

A skip commits too, since there is nothing to undo.

## 2. Send side effects after the commit

`after_commit` hooks run only when the run succeeded and the data was
committed. So the failed transfer above sent nothing:

```ruby run
NOTIFICATIONS  # => ["moved 30"]
```

Inside a transaction your app opened, the hook waits for that outer
transaction, and never runs if it rolls back:

```ruby run
Account.transaction do
  Transfer.run(from_id: ann.id, to_id: bob.id, amount: 10)
  raise ActiveRecord::Rollback
end

ann.reload.balance  # => 70
NOTIFICATIONS       # => ["moved 30"]
```

`after_commit` needs ActiveRecord 7.2 or later. Other lifecycle hooks
(`on_success`, `always`, …) run *inside* the transaction, before the commit,
so don't send email from them.

## 3. Nest it in your own transaction

Inside an open transaction the action takes its own savepoint. A failed run
rolls back only its own writes, and the rest of your transaction still commits:

```ruby run
Account.transaction do
  Transfer.run(from_id: ann.id, to_id: bob.id, amount: 999)  # fails, rolls back its credit
  Account.create!(balance: 5)                                 # still committed
end

Account.count       # => 3
bob.reload.balance  # => 30
```

Pass `transactional model: Account, requires_new: false` to join the outer
transaction instead.

## See also

- actionable USAGE: [Rails adapter](https://github.com/aemadrid-twx/actionable/blob/v1.10.0/USAGE.md#rails-adapter)
- actionable [getting started, part 2: Rails](https://github.com/aemadrid-twx/actionable/blob/v1.10.0/docs/getting_started.md#part-2--rails)
