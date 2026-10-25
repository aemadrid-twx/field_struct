---
title: How to catch a fail that doesn't stop the run
description: Turn on the Actionable/VerbNotLast RuboCop cop, so a plain fail followed by more code is caught in CI.
sidebar:
  label: Lint with the RuboCop cop
  order: 13
---

`fail`, `skip` and `succeed` record an outcome and keep going; only the bang
forms (`fail!`, `skip!`, `succeed!`) stop. So this step still charges an
expired card:

```ruby
def check_card
  fail :card_expired if card.expired?  # meant fail!
  charge(card)                         # still runs
end
```

Actionable guards against it twice. The first time an action runs, it reads
its step and hook methods and raises `Actionable::DefinitionError` for a plain
verb with code after it. The RuboCop cop applies the same rule without running
anything, so you find out in CI or in your editor.

## 1. Turn on the cop

The cop ships in the gem but isn't loaded by `require 'actionable'`. Add it to
`.rubocop.yml`:

```yaml title=".rubocop.yml"
plugins:
  - actionable-rb:
      require_path: actionable/rubocop
```

On RuboCop older than 1.72, use `require: [actionable/rubocop]` instead.

## 2. Name your base classes

The cop checks classes whose superclass is `Actionable::Action` or
`ApplicationAction`. If your actions inherit from another base, list it. The
list replaces the default, so keep the defaults you use:

```yaml title=".rubocop.yml"
Actionable/VerbNotLast:
  ActionBaseClasses:
    - Actionable::Action
    - ApplicationAction
    - Billing::BaseAction
```

## 3. Fix what it reports

Use the bang verb to stop there, or make the plain verb the method's last
expression:

```ruby
def check_card
  fail!(:card_expired) if card.expired?
  charge(card)
end
```

The cop sees one file at a time. Steps that a parent class in another file
declares are left to the first-run check.

## See also

- actionable USAGE: [Where a plain verb may go](https://github.com/Paymentbox-com/actionable/blob/v1.10.0/USAGE.md#where-a-plain-verb-may-go) (the full rule table, and how to switch the first-run check off while upgrading)
