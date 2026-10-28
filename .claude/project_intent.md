# FieldStruct — Project Intent

> What FieldStruct is, what it isn't, and the terminology used across the codebase. For the full design, decisions, and slice plan, see `docs/origin/plan.md`.

---

## What FieldStruct is

A Ruby library for building POROs ("Plain Old Ruby Objects") with declared attributes that have enforced types, presence checks, and validation.

A class collects its field declarations into a class-level **Metadata** object that can be inspected, introspected, and used downstream (e.g. to generate type signatures or documentation). Each field is backed by a **Type** class that knows how to coerce input values and decide what counts as a "missing" value. Types live in a **Registry** so different namespaces can extend or replace the base set.

A **primary goal** is legibility: the library is built to be understood and used correctly by both humans and AI agents. That goal is not decorative — it is a design invariant (see below) that constrains every public surface.

## What FieldStruct isn't

- **Not a database layer.** It doesn't persist, query, or hold connections.
- **Not a form object.** It doesn't render or know about HTTP params.
- **Not an ActiveModel replacement.** It mirrors AM's *interface shape* in places, but reuses none of its code.
- **Not a schema validator.** Validation is per-field-on-assign, not "check this hash against a schema."

---

## Capabilities (as of v0.7.1)

The library is well past the original Phase 1 cut. For the *current behavior* the
authoritative references are `README.md` and `USAGE.md`; `docs/origin/plan.md` is
the frozen design record (the "why"), not a current-state doc. At a glance, what
ships today:

- **DSL & core:** `field` / `required` / `optional`, `Base`, `Metadata`, `Registry`
  (with namespace-chain lookup and `new_registry`), per-field validation on assign.
- **Types:** string, immutable_string, integer, float, big_decimal (+`decimal`
  alias), boolean, date, time, datetime, value, `array` (`of:`), `union` (`of:
  [...]`), nested FieldStructs, and extended scalars (symbol, uuid, url, email,
  binary).
- **Field/type options:** `format:`, `enum:`, `in:`, `round:`, `values:`, callable
  `default:`, `description:`/`desc:`, plus type-level option presets.
- **Class macros (all inherited):** `coercion_policy` (class- and field-level),
  `immutable!`, `frozen!`, `unknown_attributes`, cross-field `validate`.
- **Serialization:** `serialize :json, ...` external-name mapping (replaced the
  old per-field `aliases:` in v0.4.0), JSON import (`from_json`) / output via Oj,
  round-trip equality, pattern matching (`deconstruct`/`deconstruct_keys`).
- **Tooling:** AM-shaped surface, structural equality, `RBS.generate` for
  user-defined subclasses, `Scaffold.from_json`, `metadata.to_h` introspection.

**Still deferred (Phase 2+ backlog):** custom Metadata→docs generation;
conversion to/from CSV, XML, Avro, Protobuf (separate `field_struct-<format>`
gems: they carry dependencies).

**Exporters are adapters, not core** (ruled 2026-10-27, reversing the
2026-10-25 "JSON Schema is core" ruling): JSON Schema, Avro and later Protobuf
live in the `aemadrid-twx/field_struct-adapters` monorepo as their own gems,
so an app loads only the formats it uses and each releases on its own
schedule. Core keeps `FieldStruct::Introspection`, the public field walk they
are all built on, and documents it for third-party adapters. JSON Schema
describes the canonical `to_json` output; it does not make FieldStruct a
schema validator (see "What FieldStruct isn't").

---

## Domain models and terminology

| Term | Meaning |
|---|---|
| **Field** | A single declared attribute on a FieldStruct class. Holds name, type, required-ness, default, options. |
| **Metadata** | Class-level collection of all `Field` declarations. Inherited and merged via the class hierarchy. |
| **Type** | A class under `FieldStruct::Types::*` that knows how to coerce a value, decide what counts as "missing," and report its `ruby_type`. |
| **Registry** | `FieldStruct::Registry` — name-to-type-class map. Can have a parent for fallback lookup. |
| **Base registry** | `FieldStruct.types`. Seeded with v1 types. The default when no namespace declares its own. |
| **Namespace registry** | A `Registry` exposed by a module via `self.field_types`. Used by FieldStruct subclasses defined inside that namespace. Lookup walks the full Ruby nesting chain. |
| **Coercion policy** | Class macro (`:keep_raw` / `:replace` / `:raise`) controlling what happens when a value can't be coerced. Inherited by descendants. |
| **Missing** | A value-shaped emptiness defined per type (e.g. nil-only for integers, nil-or-empty for arrays). Used by `required` to decide validity. Distinct from "key absent in input hash." |
| **Mutability** | Class macro. Default mutable. `immutable!` blocks setters after `initialize`. |
| **Unknown attributes** | Input keys that don't match any declared field. Class macro: `unknown_attributes :ignore | :raise`. |
| **Slice** | An atomic, independently shippable unit of work in the Phase 1 plan. Maps to one or more conventional commits. |

---

## Design invariants

These hold across the codebase. Don't break them without surfacing.

1. **Tests ship with code.** No "tests in a follow-up commit" — every behavior change is a `feat:` or `fix:` commit that includes its specs.
2. **Class macros are inherited.** Any new configuration knob (coercion policy, mutability, etc.) walks the class-ancestry chain to resolve its value, and descendants can override.
3. **Setters own their field's errors.** Every assignment runs the full pipeline (coerce → store → presence → format) and rewrites that field's errors entry. `valid?` is a cheap read of `errors.empty?`.
4. **Explicit `require_relative`, no autoload.** New files under `lib/field_struct/` get a corresponding `require_relative` line in `lib/field_struct.rb`.
5. **Oj for JSON.** Never `JSON.parse` / `to_json` (built-in). Always `Oj.load` / `Oj.dump`.
6. **No code reuse from ActiveModel.** Mirroring the interface shape is fine; including modules or copying internals is not.
7. **Behavior is identical with and without ActiveSupport.** Framework independence
   is not "does not depend on ActiveSupport" — it is "behaves the same whether or not
   a host has loaded it". AS adds `String#to_date` / `#to_time` / `#to_datetime` and
   redefines `Time.===`, `Date#to_time` and `Date.parse`'s two-digit-year handling, so
   **never dispatch on a predicate a framework can redefine**: branch on explicit
   stdlib classes and parse through the stdlib class methods we name
   (`Date.parse`, `Time.parse`, `strptime`), which AS does not redefine. Cross-class
   conversion is built from components rather than `to_time`/`to_datetime`, which AS
   *does* redefine. Enforced two ways: a dual CI lane (`gemfiles/activesupport_*.gemfile`,
   run under a non-UTC `TZ` with deprecations raising) and a static guard in
   `spec/guardrails_spec.rb`. The guard is necessary but not sufficient — AS changes
   semantics, not only which predicates answer true.
8. **The public surface explains itself without source.** Errors render as full sentences; `inspect` shows state *and* validity; the type system answers "what native options do I accept, and of what type" at runtime. A new public affordance that can't be understood from its own output isn't done. This is the operational form of the legibility goal — it applies to both human and agent readers.

---

## When in doubt

- Re-read `docs/origin/plan.md`.
- Re-read `docs/origin/first_discussion.md` for the original intent.
- If the answer isn't in either, ask Adrian before guessing.
