---
title: Adapters
description: Optional gems that connect field_struct and actionable to JSON Schema, Avro and OpenTelemetry, and how to write your own.
sidebar:
  label: Overview
  order: 1
---

Adapters are small, optional gems that connect field_struct and actionable to
other formats and tools. Each one is its own gem, so an app loads only the ones
it uses: an API that publishes JSON Schema doesn't pull in Avro, and a service
that never traces doesn't load OpenTelemetry. Each one releases on its own
schedule, too: a fix to the Avro adapter never waits for, or forces, a
field_struct release.

They all live in one repository,
[field_struct-adapters](https://github.com/aemadrid-twx/field_struct-adapters).

| Gem | Use it to | Built on |
|---|---|---|
| [`field_struct-json_schema`](/field_struct/adapters/json-schema/) | publish the JSON a struct writes as a JSON Schema: LLM and MCP tool parameters, API docs, request validation in other languages | `FieldStruct::Introspection` |
| [`field_struct-avro`](/field_struct/adapters/avro/) | write structs as Avro binary, with a schema, for Kafka, data lakes and schema registries | `FieldStruct::Introspection` |
| [`actionable-otel`](/field_struct/adapters/opentelemetry/) | trace every action run, step and hook in OpenTelemetry, without recording input values | actionable's run hooks |

:::caution[Not released yet]
The adapters are at 0.1.0 and unreleased. The field_struct adapters need
`FieldStruct::Introspection`, which is on field_struct's `develop` branch but not
yet in a release. Until then, install from git, as shown below. The examples in
this section run in CI against those branches, so they show what the code does
today.
:::

## Installing

Add the adapters you want. Each gem's `glob:` picks it out of the shared repository:

```ruby
# Gemfile
gem 'field_struct', git: 'https://github.com/aemadrid-twx/field_struct', branch: 'develop'

gem 'field_struct-json_schema', git: 'https://github.com/aemadrid-twx/field_struct-adapters',
                                glob: 'field_struct-json_schema/*.gemspec'
gem 'field_struct-avro',        git: 'https://github.com/aemadrid-twx/field_struct-adapters',
                                glob: 'field_struct-avro/*.gemspec'
gem 'actionable-otel',          git: 'https://github.com/aemadrid-twx/field_struct-adapters',
                                glob: 'actionable-otel/*.gemspec'
```

Then require the one you use, where you use it:

```ruby
require 'field_struct/json_schema'
require 'field_struct/avro'
require 'actionable/otel'
```

Requiring an adapter never changes your classes. Each adapter is a set of
module functions (`FieldStruct::JSONSchema.generate(User)`), plus an opt-in
`Methods` module for when you'd rather call `User.to_json_schema`.

## One shape, many formats

The field_struct adapters don't read your fields themselves. They walk them through
[`FieldStruct::Introspection`](/field_struct/adapters/introspection/), a
format-neutral view of a struct that core field_struct provides: each field's
external name, whether it's required, its default and description, and what
shape its value has (a scalar, an array, a union, or another struct). That's why
a new format is a small gem rather than a change to field_struct, and why you can
write one yourself: [Build your own adapter](/field_struct/adapters/build-your-own/)
writes a TypeScript-types generator in about 60 lines.

[How adapters work](/field_struct/adapters/how-adapters-work/) explains the
design: why separate gems, and why they share one walk.
