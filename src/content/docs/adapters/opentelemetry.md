---
title: OpenTelemetry
description: Trace every action run, step and hook in OpenTelemetry, with outcomes and result codes as attributes and no input values.
sidebar:
  order: 4
---

`actionable-otel` traces actionable in [OpenTelemetry](https://opentelemetry.io/):
one span per action run, a child span per step and hook, and the outcome and result
code as attributes. In Jaeger, Honeycomb, Datadog or Grafana Tempo you then see
where a checkout spent its time, and which step declined it. You don't need a log
line in every step.

```ruby
# Gemfile
gem 'actionable-otel', git: 'https://github.com/aemadrid-twx/field_struct-adapters',
                       glob: 'actionable-otel/*.gemspec'
gem 'opentelemetry-sdk'
gem 'opentelemetry-exporter-otlp'   # or the exporter your backend uses
```

```ruby
# config/initializers/opentelemetry.rb, or wherever your app boots
require 'opentelemetry/sdk'
require 'actionable/otel'

OpenTelemetry::SDK.configure { |c| c.service_name = 'shop' }
```

Requiring `actionable/otel` is what turns tracing on. The gem depends only on
`opentelemetry-api`; your app picks the SDK and the exporter.

## What a checkout looks like

To see the spans here, this page sends them to the SDK's in-memory exporter
rather than to a backend:

```ruby title="setup.rb" run
require 'logger'
require 'opentelemetry/sdk'
require 'actionable/otel'

SPANS = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
OpenTelemetry::SDK.configure do |c|
  c.logger = Logger.new(IO::NULL)
  c.add_span_processor(OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(SPANS))
end

def trace = SPANS.finished_spans.sort_by(&:start_timestamp).map(&:name)
```

```ruby title="checkout.rb" run
class Checkout < Actionable::Action
  input do
    required :order_id,   :string
    required :card_token, :string, sensitive: true
  end

  step :reserve_stock
  step :charge_card
  on_success :send_receipt
  on_failure :release_stock

  def reserve_stock = nil
  def charge_card
    fail!(:card_declined, 'The card was declined') if input.card_token == 'tok_declined'
  end
  def send_receipt = nil
  def release_stock = nil
end
```

A successful run is one trace, with a span per step and hook:

```ruby run
Checkout.run(order_id: 'ord_1', card_token: 'tok_visa')

trace   # => ["Checkout.run", "Checkout/reserve_stock", "Checkout/charge_card", "Checkout/send_receipt"]
run = SPANS.finished_spans.find { |span| span.name == 'Checkout.run' }
run.attributes['actionable.outcome']   # => "success"
```

A declined card marks the run span as an error, with the code as its
description and as an attribute, and runs the failure hook instead:

```ruby run
SPANS.reset
Checkout.run(order_id: 'ord_2', card_token: 'tok_declined')

trace   # => ["Checkout.run", "Checkout/reserve_stock", "Checkout/charge_card", "Checkout/release_stock"]
run = SPANS.finished_spans.find { |span| span.name == 'Checkout.run' }
run.attributes['actionable.code']   # => "card_declined"
run.status.code == OpenTelemetry::Trace::Status::ERROR   # => true
run.status.description              # => "card_declined"
```

In your backend, filter on `actionable.code` to tell declared failures
(`card_declined`, `not_found`) apart from exceptions. A skip isn't an error; its
status stays unset.

## What it never records

Input and output values, messages and errors stay out of the spans. They often
hold card numbers, tokens or personal data:

```ruby run
recorded = SPANS.finished_spans.flat_map { |span| span.attributes.values }
recorded.any? { |value| value.to_s.include?('tok_') }   # => false
```

An exception that escapes a run is recorded once, on the run span, with only its
class (`exception.type`): a message or backtrace can carry input values too. Set
`Actionable::Otel.exception_details = :full` to record the message and backtrace
as well.

## Attributes

| Attribute | On | Value |
|---|---|---|
| `actionable.action` | run and step spans | the action's class name |
| `actionable.outcome` | run spans | `success`, `failure` or `skipped` |
| `actionable.code` | run spans, and the step span that set the result | the result code |
| `actionable.step` | step spans | the method name, or the nested action's class |
| `actionable.step.kind` | step spans | `method`, `action` or `case` |
| `actionable.section` | step spans | `main`, `success`, `failure`, `skip` or `always` |

A nested action's run span sits under its parent's step span when it runs on
the same thread and fiber, so a composed action is one trace.

## Cost and volume

- **Cost:** about 5 µs per span with the SDK. That's measured on a CPU-bound
  action with 10 spans per run, and is negligible next to a database call.
- **Fewer spans:** in a tight `run_each` over many thousands of items, set
  `Actionable::Otel.step_spans = false` to keep only the run spans.
- **Sampling** is OpenTelemetry's: use the SDK's sampler to keep a fraction of traces.
