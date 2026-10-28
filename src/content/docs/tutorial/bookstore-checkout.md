---
title: Build a bookstore checkout
description: A hands-on introduction to FieldStruct and Actionable, in six short chapters.
sidebar:
  label: Overview
  order: 1
---

Let's build the checkout for a small online bookstore, one piece at a time.
Each chapter builds on the one before it:

1. [A typed Book](../a-typed-book/): define a struct with typed fields,
   required and optional fields, defaults, validation and coercion.
2. [Orders and JSON](../orders-and-json/): nest line items inside an `Order`,
   turn it into JSON and back, rename JSON keys and hide sensitive values.
3. [Placing the order](../placing-the-order/): write a `PlaceOrder` action with
   steps, typed input and output, and a declared `:out_of_stock` failure.
4. [When things go wrong](../when-things-go-wrong/): handle every outcome at
   the call site with skips, metadata, errors as data and `case`/`in`.
5. [Composing actions](../composing-actions/): split checkout into small
   actions, run them as steps of one parent, and undo with a hook.
6. [Into an app](../into-an-app/): call the checkout from a controller, run it
   in a background job with retries, and test it with RSpec.

Chapters 1 and 2 use [FieldStruct](https://github.com/aemadrid-twx/field_struct),
which gives you typed plain-Ruby objects. Chapters 3 to 6 add
[Actionable](https://github.com/aemadrid-twx/actionable), which builds
service objects on top of FieldStruct.

## Before you start

You need Ruby 3.3 or newer and both gems in your `Gemfile`:

```ruby title="Gemfile"
gem 'field_struct', git: 'https://github.com/aemadrid-twx/field_struct', tag: 'v0.16.0'
gem 'actionable-rb', git: 'https://github.com/aemadrid-twx/actionable', tag: 'v1.10.0'
```

[Chapter 6](../into-an-app/) also uses `activejob` and `rspec`, and it says
when to add them. Run `bundle install`, then follow along in `bundle exec irb`
with `require 'field_struct'` and `require 'actionable'`, or in a script.

Every example in this tutorial runs in CI against exactly these releases, and
each `# => value` comment is checked. So when you see `# =>`, that is what Ruby
returns.
