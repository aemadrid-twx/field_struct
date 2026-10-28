---
title: How adapters work
description: Why formats like JSON Schema and Avro are separate gems, why they share one walk, and what that means when you upgrade.
sidebar:
  order: 7
---

field_struct describes a payload once, as a Ruby class. Plenty of other tools want
that same description in their own language: JSON Schema for validators and LLM
tools, Avro for Kafka and data lakes, TypeScript for a frontend, Protobuf for
gRPC. This page explains how the gems split that work, and why.

## Why separate gems

Each format brings its own dependencies and its own pace of change. Avro needs the
`avro` gem; OpenTelemetry needs `opentelemetry-api`. JSON Schema needs nothing,
but its regular-expression translation is a few hundred lines most apps would
never run. If every format lived in field_struct, every app would install and
load all of it.

As separate gems:

- **An app loads what it uses.** A JSON API that never touches Kafka has no Avro
  code in its process.
- **Dependencies are declared.** `actionable-otel` can require a working range of
  `opentelemetry-api` in its gemspec. Inside actionable it could only hope the
  app had installed a compatible one.
- **Each releases on its own.** A fix to the Avro mapping ships as a
  `field_struct-avro` release. field_struct doesn't change, so apps that don't
  use Avro have nothing to upgrade. The reverse holds too: a field_struct release
  that doesn't change the walk needs no adapter release.

The cost is coordination: a change to the walk can break an adapter. Two things
contain that. The walk is public API, so a breaking change to it comes with a
version bump and an entry in field_struct's upgrade guide, like any other
breaking change. And the adapters' CI runs every night against field_struct's
newest code, so a break shows up the next morning, not when you upgrade.

## Why one walk

Every exporter needs the same answers about a struct:

- What is each field called in the output?
- Is it required, and what's its default?
- Is the value a scalar, an array, a choice between types, or another struct?
- How do I avoid looping forever on a struct that contains itself?

field_struct already knows all of that, but it's spread across field options,
type classes and the `serialize` mapping. If every exporter dug those answers out
on its own, each would get the edge cases slightly differently: an array of
unions, an anonymous nested struct.
[`FieldStruct::Introspection`](/field_struct/adapters/introspection/) answers them
once, in four node types, and every adapter is a `case` over those four. When
the JSON Schema exporter was moved onto it, all 520 schemas its test suite
generates came out byte-for-byte the same.

That also decides what stays in core. The walk stays: it changes when
field_struct's fields change, so it has to live with them. The formats move
out: they change when their target changes, like a new Avro logical type or a
new JSON Schema draft.

## Why adapters describe the JSON

An adapter describes what `to_json` writes, not what the setters accept. A
setter takes `age: "30"` and coerces it, but the JSON says `30`, and that's what
another system receives. So a BigDecimal is a string in JSON Schema and
TypeScript (`to_json` writes `"24.99"`), but an exact decimal in Avro, which
encodes the value itself rather than JSON.

## Why never approximate

When a feature has no exact equivalent in the target format, the adapters leave
it out or raise rather than guess. A Ruby Regexp with no exact ECMA-262
translation isn't approximated in JSON Schema. A time with more precision than
an Avro timestamp holds raises an error rather than being truncated.

A near miss is worse than nothing. A pattern that's slightly too strict makes
another service reject payloads Ruby accepted. A silently truncated timestamp is
a bug you find months later in a warehouse.

## What adapters may rely on

Adapters read only field_struct's public surface: `Introspection` and its node
classes, `Field`'s documented methods, and the type classes. Each adapter keeps
its options under its own name (`avro:`, `json_schema:`), so adapters never
collide, and field_struct passes options it doesn't use through to them. Each
adapter declares the field_struct versions it supports in its gemspec. Until
field_struct releases Introspection, that floor is `>= 0.16`, which the
released 0.16.0 (without Introspection) satisfies, so each adapter also checks
at `require` time and raises a `LoadError` that says what's missing. Once the
floor is raised to that release, an incompatible combination fails at
`bundle install` instead.
