---
title: ActiveModel-shaped, framework-free
description: Why field_struct's methods look like ActiveModel's without using its code, and why both gems behave the same with or without Rails loaded.
sidebar:
  order: 4
---

If you have used Rails, a FieldStruct feels familiar: `valid?`, `errors`,
`attributes`, `as_json`, `model_name`. None of that comes from Rails. Neither
gem depends on ActiveModel or ActiveSupport. And field_struct goes one step
further: it promises to behave the same whether or not your app has loaded
them.

## The shape, not the code

Decision D8 in the field_struct
[design record](https://github.com/aemadrid-twx/field_struct/blob/v0.16.0/docs/origin/plan.md):
"We mirror the shape so Rails-adjacent developers feel at home, but we do not
reuse `ActiveModel::*` code." It is also a design invariant: "Mirroring the
interface shape is fine; including modules or copying internals is not."

```ruby run
class Contact < FieldStruct::Base
  required :first_name, :string
end

contact = Contact.new
contact.valid?                 # => false
contact.errors.full_messages   # => ["First name is required"]
contact.model_name.name        # => "Contact"
contact.model_name.plural      # => "contacts"
contact.to_model.equal?(contact)  # => true
```

`errors` is a `FieldStruct::Errors` and `model_name` a
`FieldStruct::ModelName`: small value objects with the familiar methods, written
for the gem.

Some ActiveModel methods are left out on purpose. D8 skips `to_key`,
`to_param`, `to_partial_path`, `persisted?` and `new_record?` because "they
encode a persistence/identity model FieldStruct does not have." That matches
what the project says it is not: "Not a database layer. Not a form object. Not
an ActiveModel replacement"
([project intent](https://github.com/aemadrid-twx/field_struct/blob/v0.16.0/.claude/project_intent.md)).

The records state the no-reuse rule but don't give a further reason for it.
What they do record is the outcome: field_struct's only runtime dependencies
are `bigdecimal`, `oj` and `tzinfo` (`field_struct.gemspec`).

## Same behaviour, with or without ActiveSupport

Not depending on ActiveSupport is not enough. A host app usually loads it
anyway, and ActiveSupport changes core Ruby classes. field_struct's invariant 7
puts it this way: framework independence "is not 'does not depend
on ActiveSupport', it is 'behaves the same whether or not a host has loaded
it'."

The invariant lists what ActiveSupport changes. It adds `String#to_date`,
`#to_time` and `#to_datetime`, and it redefines `Time.===`, `Date#to_time` and
`Date.parse`'s two-digit-year handling. So the rule is "**never dispatch on a
predicate a framework can redefine**":

- branch on explicit stdlib classes, not on `respond_to?(:to_date)`
- parse through the stdlib class methods (`Date.parse`, `Time.parse`,
  `strptime`), which ActiveSupport doesn't redefine
- build cross-class conversions from components rather than through
  `to_time` / `to_datetime`, which it does

We enforce it two ways. A CI lane runs the suite with ActiveSupport 7.2 and 8.1
loaded, under `TZ=America/Denver` with deprecations raising. And a static guard
lives in `spec/guardrails_spec.rb`. The invariant itself warns the guard "is
necessary but not sufficient": ActiveSupport changes semantics, not only which
predicates answer true.

You can see the rule at the edges of the API. The `zone:` option refuses Rails
zone names such as `"Mountain Time (US & Canada)"`. USAGE explains: "They are
ActiveSupport aliases that exist only when ActiveSupport is loaded, so
accepting them would make the same declaration valid in one process and
invalid in another." Use the IANA name instead (`"America/Denver"`).

## actionable: a pure-Ruby core with opt-in adapters

actionable makes the same split at the gem level. Its core "depends only on
`field_struct`" (plus `oj`, which field_struct already pulls in), and nothing under the core load path requires ActiveModel,
ActiveSupport or ActiveRecord (decision D8 and invariant 4 in the actionable
[design record](https://github.com/aemadrid-twx/actionable/blob/v1.10.0/docs/origin/plan.md)).
The Rails pieces live behind explicit requires:

| Require | Adds |
|---|---|
| `actionable` | the core: actions, steps, results |
| `actionable/rails` | `transactional`, `after_commit`, `ProxyValidator` |
| `actionable/job` | mapping a result to a queue disposition |
| `actionable/rspec` | matchers and stubs |

This one has a reason on record. The original actionable "always loaded
ActiveModel/ActiveSupport and hard-wired ActiveRecord transactions". The
rebuild moved them to an opt-in adapter as one of four fixes for code that was
"hard to type and hard for both humans and coding agents to reason about"
([first discussion](https://github.com/aemadrid-twx/actionable/blob/v1.10.0/docs/origin/first_discussion.md)).

## Related

- [How the two gems fit together](../how-the-gems-fit/)
- [USAGE: Zones](https://github.com/aemadrid-twx/field_struct/blob/v0.16.0/USAGE.md#zones-zone)
