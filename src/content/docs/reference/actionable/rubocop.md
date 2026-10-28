---
title: RuboCop cop
description: "Actionable/VerbNotLast: enabling the cop, ActionBaseClasses and what it checks."
sidebar:
  order: 12
---

The gem ships one cop, `Actionable/VerbNotLast`. It applies the same rules as
the [first-run verb-position check](../control-flow/#where-a-plain-verb-may-go),
from the same analyzer, as a lint: a plain `fail` / `fail_with` / `skip` /
`succeed` must be the last expression of its step or hook method. It is not
loaded by `require 'actionable'`, and it has no autocorrect.

## Enabling it

RuboCop 1.72 and later (plugin API, through `lint_roller`):

```yaml
# .rubocop.yml
plugins:
  - actionable-rb:
      require_path: actionable/rubocop
```

Older RuboCop:

```yaml
require:
  - actionable/rubocop
```

The cop is enabled by default once loaded. Its default configuration:

```yaml
Actionable/VerbNotLast:
  Enabled: true
  ActionBaseClasses:
    - Actionable::Action
    - ApplicationAction
```

## `ActionBaseClasses`

A class is checked when its superclass is one of these (full names; a leading
`::` is ignored). It is also checked when its superclass is a class defined in
the same file (`class Base < …` or `Base = Class.new(…)`, at any depth) whose
own superclass chain reaches one. The
superclass name resolves the way Ruby looks it up, from the enclosing modules
outwards, so two same-named classes in different modules are told apart. List
your own base classes. The list _replaces_ the default, so keep the defaults if
you still need them:

```yaml
Actionable/VerbNotLast:
  ActionBaseClasses:
    - Actionable::Action
    - ApplicationAction
    - Billing::BaseAction
```

Any other class is left alone. So a class with its own `step` DSL (say,
`include Dry::Transaction`) gets no false positives, and neither does a class
that reopens an action without naming its superclass.

## What it sees

The cop sees one file. In an action class that declares `step` or `case_step`,
it checks the methods that class names in a step, a case-step branch or a hook
declaration. Methods a parent class declares as steps are left to the first-run
check, which also follows a step that names an `alias_method` (the cop doesn't).

The offense message:

```text
`fail` records the outcome and keeps running, and more code runs after it: use `fail!` to stop here, or make it the method's last expression.
```

```ruby
# bad
def charge
  fail :card_expired if card.expired?
  notify
end

# good
def charge
  fail! :card_expired if card.expired?
  notify
end

# good
def charge
  notify
  fail :card_expired if card.expired?
end
```

When the first-run check is switched off with
`Actionable.verb_position_check = false`, this cop is the only guard, so keep it
in CI.

Upstream: [USAGE, Control flow](https://github.com/aemadrid-twx/actionable/blob/v1.10.0/USAGE.md#where-a-plain-verb-may-go).
