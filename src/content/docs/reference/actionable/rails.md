---
title: Rails adapter
description: "actionable/rails: the transactional macro, after_commit hooks and ProxyValidator."
sidebar:
  order: 9
---

`require 'actionable/rails'` loads the optional adapter. It requires
`active_model` and ActiveSupport's string inflections, and defines a Railtie
when Rails is loaded. The core never loads it, so without it there is no
`transactional`:

```ruby run
Actionable::Action.respond_to?(:transactional)   # => false
Actionable::Action.respond_to?(:after_commit)    # => false
```

The examples below are not run on this site (it doesn't install ActiveRecord).
CI for the gem runs the adapter on ActiveRecord 7.1 and 8.x. Only
`after_commit` needs 7.2.

## `transactional`

```ruby
class CreateInvoice < Actionable::Action
  transactional model: :invoice                       # Invoice.transaction { … }
  # transactional model: Invoice, requires_new: false  # a class works too
end
```

`transactional(model:, **options)` wraps the whole run, steps and hooks, in
`model.transaction(**options)`. `model:` is a class, or a Symbol/String turned
into one with `camelize.constantize` (`:invoice` → `Invoice`).

| Outcome | Transaction |
|---|---|
| `Success` | commits |
| `Skipped` | commits |
| `Failure` (recorded) | rolls back; `.run` still returns the failure |
| an exception raised | rolls back and the exception propagates |

- **Nesting.** When a transaction is already open on the model's connection
  and you didn't pass `requires_new:`, the action adds `requires_new: true`. So
  it takes its own savepoint, and its failed writes roll back without the outer
  transaction committing them. Pass `requires_new: false` to join the outer
  transaction instead.
- Lifecycle hooks run inside the transaction, so a hook's writes share its
  fate and its external side effects fire before the commit.
- The setting is inherited. `transaction_config` reads it as
  `{model:, options:}`, and `describe[:transactional]` shows it.

## `after_commit`

```ruby
class PlaceOrder < Actionable::Action
  transactional model: :order
  step :save
  after_commit :send_receipt
  after_commit Notify, input: %i[order], if: :notify?
end
```

`after_commit target, **options` runs a side effect only after the database work
really committed. A target is a method or an action class, with `if:` /
`unless:` like any hook. It needs ActiveRecord ≥ 7.2
(`ActiveRecord.after_all_transactions_commit`). Declaring it on an older
ActiveRecord, or without ActiveRecord loaded, raises `DefinitionError`.

| Scenario | Runs? | When |
|---|---|---|
| `transactional` action succeeds at the top level | yes | right after its transaction commits, before `.run` returns |
| succeeds inside an outer `Model.transaction` | yes | after the **outermost** transaction commits |
| succeeds, then an enclosing transaction rolls back | no | — |
| the run ends in a `Failure` | no | — |
| the run ends in a `Skipped` | no | the skip's writes commit, but there is nothing to do |
| non-transactional action, no transaction open | yes | immediately after the run, before `.run` returns |
| nested actions, each with `after_commit` | each once, child first | after the outermost commit |

The run is over when the hook fires: it can't change the result (a halting verb
only stops the remaining `after_commit` hooks) and it is not recorded in the
history. An exception it raises propagates from wherever the commit happened.
`after_commit` hooks are inherited, checked by the missing-method and
verb-position checks, listed under `describe[:hooks][:after_commit]`, and read
with `after_commit_hooks`.

## `Actionable::ProxyValidator`

A class that includes `ActiveModel::Validations` and forwards every other method
to a delegate, so you can run ActiveModel rules against any object:

```ruby
class InvoiceValidator < Actionable::ProxyValidator
  validates :amount, presence: true
end

validator = InvoiceValidator.new(invoice)
validator.formatted_errors   # => { amount: ["can't be blank"] }  (runs valid? first)
```

`formatted_errors` runs `valid?` and returns `errors.to_hash`, ready to splat into
`fail!(:invalid, nil, **validator.formatted_errors)`. `delegate` returns the
wrapped object.

Upstream: [USAGE, Rails adapter](https://github.com/aemadrid-twx/actionable/blob/v1.10.0/USAGE.md#rails-adapter).
