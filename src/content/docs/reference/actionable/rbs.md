---
title: RBS for your actions
description: "Actionable::RBS.generate: the signatures it emits for .run, input, output, results, failure and skip codes, typed outcomes and base classes."
sidebar:
  order: 11
---

The gem ships Sord-generated signatures for its own classes (`sig/`).
`Actionable::RBS.generate(klass)` writes RBS for **your** action from its
declared schemas, so Steep or Solargraph can check `.run` calls and result
readers. It returns a String.

| Argument | Result |
|---|---|
| a named `Actionable::Action` subclass | its RBS |
| an anonymous action | `ArgumentError` (`cannot generate RBS for an anonymous action`) |
| anything else | `ArgumentError` (`Actionable::RBS.generate expects an Actionable::Action subclass, got String`) |

## An action with input and output

```ruby run
class CreateInvoice < Actionable::Action
  fails :refused
  skips :not_ready
  input do
    required :amount, :integer
    optional :tags, :array, of: :string
  end
  output { required :total, :integer }
  step :compute
  def compute = @total = input.amount * 2
end

expected = <<~RBS
  class CreateInvoice < ::Actionable::Action
    type failure_code = :refused | :invalid_input | :invalid_output
    type skip_code = :not_ready

    def self.run: (amount: ::Integer, ?tags: ::Array[::String?]?) -> Result
                | (InputSchema input) -> Result

    def input: () -> InputSchema

    @total: ::Integer?

    class InputSchema < ::FieldStruct::Base
      attr_reader amount: ::Integer
      def amount=: (::Integer? value) -> ::Integer?
      attr_reader tags: ::Array[::String?]?
      def tags=: (::Array[::String?]? value) -> ::Array[::String?]?
    end

    class Output < ::FieldStruct::Base
      attr_reader total: ::Integer
      def total=: (::Integer? value) -> ::Integer?
    end

    class Result < ::Actionable::Result
      def output: () -> Output
      def total: () -> ::Integer
    end
  end
RBS

Actionable::RBS.generate(CreateInvoice) == expected   # => true
```

What each part is:

| Part | From |
|---|---|
| `type failure_code` | declared failure codes, then `GEM_FAILURE_CODES`; only when the action declares failures |
| `type skip_code` | declared skip codes only; only when the action declares skips |
| `def self.run` | the input schema's fields as keywords (optional fields prefixed `?`), or an `InputSchema` instance. A free-form or `input_for` action gets `(*untyped)` |
| `def input` | only with a fixed `input` schema |
| `@field: T?` | one per output field, so steps that assign it type-check; nullable because it's unset until assigned. Don't declare these again in your own sig files: RBS rejects an instance variable declared twice |
| `InputSchema`, `Output`, `Result` | exist only in RBS. At runtime the schemas are anonymous classes |
| `Result` | `output` typed as `Output`, plus one reader per output field. Without an output schema, `.run` returns `::Actionable::Result` |

Field types come from `FieldStruct::RBS.type_for`, so they match what
`FieldStruct::RBS.generate` emits: writers take and return `T?`, scalar array
elements are nullable, a field's `rbs_type:` wins, and a `:value` field is
`untyped`. Types describe a valid instance.

Generation raises `ArgumentError` when the action has a fixed `input` schema and
Ruby already resolves `YourAction::InputSchema` (a constant on the action, an
ancestor or an included module), since the RBS name would describe something
else.

## Typed outcomes

Under [`typed_outcomes`](../declared-outcomes/#typed-outcomes), `.run` returns
`(Success | Skipped | Failure)`, the action's own classes, each with its `code`
and `output` narrowed:

```ruby run
class ActivateKey < Actionable::Action
  typed_outcomes
  input  { required :id, :integer }
  output { required :id, :integer }
  skips(:already_active) { required :id, :integer }
  fails(:invalid) { optional :field, :string }
  step :activate
  def activate = @id = input.id
end

rbs = Actionable::RBS.generate(ActivateKey)
rbs.include?('def self.run: (id: ::Integer) -> (Success | Skipped | Failure)')   # => true
rbs.include?('class AlreadyActiveSkipOutput < ::FieldStruct::Base')              # => true
rbs.include?('def output: () -> (AlreadyActiveSkipOutput | ::Hash[::Symbol, untyped])')   # => true
rbs.include?('def output: () -> (InvalidFailureOutput | AlreadyActiveSkipOutput | Output | ::Hash[::Symbol, untyped])')   # => true
rbs.include?('def id: () -> ::Integer?')                                        # => true
```

- `Success#code` is `:success`, `Skipped#code` is `skip_code`, `Failure#code` is
  `failure_code`. A code with no schema, or no declarations at all, types as a
  Hash output and a plain `::Symbol` code.
- A failure's output also admits every skip schema and `Output`, because output
  that breaks one ends the run as `invalid_output` carrying it. For the same
  reason every reader declared on `Failure` is nullable.
- Each per-code output class is named after its code, camelized, plus
  `SkipOutput` or `FailureOutput`. A trailing `?` becomes `Predicate` and `!`
  becomes `Bang` (`fails(:expired?) { … }` → `ExpiredPredicateFailureOutput`).
  `generate` raises `ArgumentError` when two codes of one kind land on one name
  (`:ready` and `:ready_`), or when a code's name isn't plain ASCII starting with a
  capital once camelized.
- A host's own result subclass returned by `.run` is not described (a known gap
  upstream).

## Base actions

The action is declared with its real superclass, and every named ancestor up to
`Actionable::Action` is declared before it, empty, so the file validates even if
nobody generates your abstract bases:

```ruby run
class ApplicationAction < Actionable::Action; end

module Codes
  class BaseAction < ApplicationAction; end

  class DecideMapping < BaseAction
    output { required :id, :integer }
  end
end

rbs = Actionable::RBS.generate(Codes::DecideMapping)
rbs.start_with?("class ApplicationAction < ::Actionable::Action\nend\n\nmodule Codes\n  class BaseAction < ::ApplicationAction\n  end\nend\n")   # => true
rbs.include?('class DecideMapping < ::Codes::BaseAction')   # => true
rbs.include?('def self.run: (*untyped) -> Result')          # => true
```

Write each action's RBS to its own file: the repeated ancestor declarations are
byte-identical and RBS merges them. A namespace that is a class opens as `class`
(without a superclass). An anonymous ancestor is skipped. A subclass of a typed
action subclasses its parent's result classes
(`class Success < ::Billing::BaseAction::Success`).

Upstream: [USAGE, RBS for your actions](https://github.com/Paymentbox-com/actionable/blob/v1.9.0/USAGE.md#rbs-for-your-actions).
