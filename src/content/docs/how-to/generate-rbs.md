---
title: How to generate RBS signatures for your classes
description: Give Steep or Solargraph types for the readers your fields create and for each action's run, input and output.
sidebar:
  label: Generate RBS signatures
  order: 12
---

Fields and actions define methods at runtime, so a type checker can't see them.
Both gems can write the RBS for you, and both generators are loaded with the
gems.

## Structs

`FieldStruct::RBS.generate` returns the signature of one struct class as a
String. A required field reads as `T`, an optional one as `T?`:

```ruby title="order.rb" run
class LineItem < FieldStruct::Base
  required :sku,      :string
  required :quantity, :integer
end

class Order < FieldStruct::Base
  required :id,    :uuid
  optional :lines, :array, of: LineItem
end

rbs = FieldStruct::RBS.generate(Order)
rbs.include?('class Order < ::FieldStruct::Base')         # => true
rbs.include?('attr_reader id: ::String')                  # => true
rbs.include?('attr_reader lines: ::Array[::LineItem]?')   # => true
```

The types describe a *valid* instance. An invalid one can hold `nil` in a
required field, or the raw input that failed to coerce, so check `valid?`
before you trust them. Generate the nested classes too (`LineItem` here), so
`::LineItem` resolves.

## Actions

`Actionable::RBS.generate` types `.run` from the `input` block, and the result's
output readers from the `output` block:

```ruby title="place_order.rb" run
class PlaceOrder < Actionable::Action
  fails :out_of_stock

  input  { required :order, Order }
  output { required :total_cents, :integer }

  step :total
  def total = @total_cents = 0
end

rbs = Actionable::RBS.generate(PlaceOrder)
rbs.include?('def self.run: (order: ::Order) -> Result')                            # => true
rbs.include?('def total_cents: () -> ::Integer')                                     # => true
rbs.include?('type failure_code = :out_of_stock | :invalid_input | :invalid_output') # => true
```

`InputSchema`, `Output` and `Result` in that output exist only in RBS; at
runtime the input and output schemas are anonymous classes.

## Write the files

Regenerate the files from a Rake task whenever the classes change, one file per
class:

```ruby title="lib/tasks/rbs.rake"
require 'fileutils'

namespace :rbs do
  task :generate do
    FileUtils.mkdir_p('sig/generated')

    { 'line_item' => LineItem, 'order' => Order }.each do |file, klass|
      File.write("sig/generated/#{file}.rbs", FieldStruct::RBS.generate(klass))
    end

    { 'place_order' => PlaceOrder }.each do |file, action|
      File.write("sig/generated/#{file}.rbs", Actionable::RBS.generate(action))
    end
  end
end
```

The task isn't run on this page; in a Rails app, make it depend on
`:environment` so the classes load. If your actions share a base class (an
`ApplicationAction`), each action's file declares that base too, empty, so the
files repeat those lines; RBS merges them. Don't declare an action's output instance variables (`@total_cents`) in
your own sig files too: the generated file already does, and RBS rejects a
second declaration.

## See also

- field_struct USAGE: [RBS for your own classes](https://github.com/Paymentbox-com/field_struct/blob/v0.16.0/USAGE.md#rbs-for-your-own-classes)
- actionable USAGE: [RBS for your actions](https://github.com/Paymentbox-com/actionable/blob/v1.10.0/USAGE.md#rbs-for-your-actions)
