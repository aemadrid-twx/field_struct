---
title: Build a bookstore checkout
description: A hands-on introduction to FieldStruct and Actionable, in three short chapters.
sidebar:
  label: Overview
  order: 1
---

In this tutorial you'll build the checkout for a small online bookstore, one
piece at a time. Each chapter builds on the one before it:

1. [A typed Book](../a-typed-book/): define a struct with typed fields,
   required and optional fields, defaults, validation and coercion.
2. [Orders and JSON](../orders-and-json/): nest line items inside an `Order`,
   turn it into JSON and back, rename JSON keys and hide sensitive values.
3. [Placing the order](../placing-the-order/): write a `PlaceOrder` action with
   steps, typed input and output, and a declared `:out_of_stock` failure.

Chapters 1 and 2 use [FieldStruct](https://github.com/Paymentbox-com/field_struct),
which gives you typed plain-Ruby objects. Chapter 3 adds
[Actionable](https://github.com/Paymentbox-com/actionable), which builds
service objects on top of FieldStruct.

## Before you start

You need Ruby 3.2 or newer and both gems in your `Gemfile`:

```ruby title="Gemfile"
gem 'field_struct', git: 'https://github.com/Paymentbox-com/field_struct', tag: 'v0.15.0'
gem 'actionable-rb', git: 'https://github.com/Paymentbox-com/actionable', tag: 'v1.9.0'
```

Run `bundle install`, then follow along in `bundle exec irb` with
`require 'field_struct'` and `require 'actionable'`, or in a script.

Every example in this tutorial is run in CI against exactly these releases, and
each `# => value` comment is checked. If you see `# =>`, that's what Ruby returns.
