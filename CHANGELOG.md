# Changelog

All notable changes to FieldStruct are recorded here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); the project
adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- `FieldStruct::JSONSchema.generate(klass)` and `Klass.to_json_schema`: a JSON
  Schema (draft 2020-12) of the JSON a class writes with `to_json`. Covers every
  built-in type, `serialize :json` names, `enum:` / `in:` / Regexp `format:`
  (translated to ECMA-262, else kept as `x-ruby-pattern`), nested structs in
  `$defs` (recursion via `$ref: "#"`), arrays, unions, `description:`, literal
  defaults, `sensitive:` and `unknown_attributes :raise`. Overrides: a field's
  `json_schema:` option and a custom type's new `Types::Base#json_schema`. No
  runtime dependency; the spec checks generated schemas against `to_json`
  output with `json_schemer` (dev only).
- `FieldStruct::JSONSchema.pattern_for(regexp)`: a Ruby Regexp as an ECMA-262
  pattern that matches the same strings with or without the `u` flag (`.`,
  `\s`, `^` / `$` and `/i` keep Ruby's meaning), or `nil` when there's no exact
  translation. Every built-in UUID, URL and Email format translates.

### Changed

- `describe` shows each field's `desc:` after its type (`name (String, required) — "Full legal name" — accepts …`), and a nested struct field names its class (`home (Address, optional)`, was `home (Nested, optional)`), so a reader knows which class to `describe` next. An anonymous nested struct still shows `Nested`. <!-- upgrading: none -->

### Documentation

- USAGE spells out the `:boolean` strings: by default only `"true"`, `"1"`,
  `"false"`, `"0"` (case-insensitive); `"yes"` needs `values: :english_yes_no`,
  and a `values:` Hash replaces the defaults rather than adding to them. Doctested.
- USAGE lists `format:` (Regexp) and `enum:` for `:binary`, which it already
  accepted and enforced.
- USAGE says which RFC 3339 forms `format: :iso8601` reads: lowercase `t` / `z`
  and a `±hhmm` offset are accepted along with `T`, `Z` and `±hh:mm`.
- USAGE notes that `Z` under `format: :iso8601` gives a fixed `+00:00` offset
  (`utc?` is false, `zone: 'UTC'` doesn't change it), with a doctest.
- USAGE "Introspection" shows that `metadata.to_h` renders an array of structs
  as `of_type: "Nested"` without the class, and how to read the class. Doctested.
- README, USAGE and the `ModelName#plural` YARD note that the plural only
  appends "s" (`Address` → `"addresss"`).
- Fixed a missing comma in USAGE's `inspect` example, the `Base.resolve_type`
  YARD (lookup goes innermost module first, not outermost), and invariant
  numbers that didn't match `.claude/project_intent.md` (ActiveSupport parity
  is 7, self-explaining surface is 8) in USAGE and two `base.rb` comments.

## [0.16.0] - 2026-10-25

Ruby 3.3 or newer is now required; the library itself is unchanged, so on
Ruby 3.3+ this is a drop-in bump from 0.15.0 (`UPGRADING.md` "0.15 → 0.16").
The gem is now MIT-licensed (earlier releases shipped no license). The rest is
docs: a README example that didn't parse is fixed and a spec now parses every
Ruby block in the docs, USAGE says exactly what `as_json` / `to_json` hold, and
the README installs from RubyGems. CI runs on our own self-hosted runners.

### Changed

- **Ruby 3.3 or newer is required** (`required_ruby_version >= 3.3.0`, was
  `>= 3.0.0`). 3.3 is the oldest Ruby a known client runs; dropping 3.0–3.2
  lets CI run on our own Ubuntu 26.04 runners, where Ruby 3.0 can't build
  against OpenSSL 3. The library code is unchanged. CI drops the 3.2 lane and
  the 3.0/3.1 floor job (and `gemfiles/floor.gemfile`); RuboCop targets 3.3.
  **Upgrade note:** on Ruby 3.0–3.2, stay on 0.15.x.
  <!-- upgrading: ruby-floor-3-3 -->

### Fixed

- README's `in:` example `required :height, :integer, in: 10..` didn't parse: a
  bare endless range at the end of a line takes the next line as its end. It now
  reads `in: (10..)`. A new spec parses every ```ruby block in the docs, doctest
  or not, so a broken example fails CI.

### Documentation

- USAGE "JSON & serialization" now says what the output holds: `as_json` has
  Symbol keys, every field is written (unset optionals as `nil` / `null`), and
  there is no per-call `only:` / `except:`, with a doctested way to leave a
  field out. Gaps found by the docs-site tutorial.
- README installs from RubyGems (`gem 'field_struct'`); 0.15.0 is published there.

### Added

- **MIT license.** The gem now ships `LICENSE.txt` and declares `spec.license = 'MIT'`;
  earlier releases (0.15.0 and before) shipped no license.

## [0.15.0] - 2026-10-23

Faster, with two small behaviour changes. `new` is about 45% faster and
allocates 11 objects instead of 39 for five fields; `to_json` takes about a
third less time; validation-heavy structs are nearly twice as fast (medians of
interleaved runs on an M4, PR #41). Two changes are
visible, both silent and both in `UPGRADING.md` "0.14 → 0.15": `new` no longer
runs a field's setter with `nil` before the value you gave it, and `as_json`
reads the fields directly, so an `attributes` override no longer shapes the
JSON. Every other change keeps output byte-identical.

### Changed

- **`new` skips the nil default for keys it is given.** A field with no `default:` whose key the input carries is no longer first set to `nil` through its setter: an overridden setter runs once, with the given value, and under `coercion_policy :raise` a custom type that refuses `nil` no longer raises from `new` for a given key. Non-Hash input is refused before callable defaults run. Values, errors and ivar order are unchanged. <!-- upgrading: defaults-skip-nil-pass -->
- **`as_json` / `to_json` read the declared fields, not `attributes`.** One pass over the fields, each read through its reader, instead of building `attributes` and walking it again. An `attributes` override no longer changes the JSON; a reader override still does. `attributes` and `to_h` are unchanged. <!-- upgrading: as-json-reads-fields -->
- **Faster `new`, `from_json` and `:date` parsing; fewer allocations.** Setter and ivar names are built once per field instead of per assignment, a `:date` string is parsed once rather than twice, `from_json` reuses its reverse `serialize :json` map, arrays without nested structs skip the per-element validity scan, `Errors#empty?` no longer allocates, and the inherited class macros stop walking at `FieldStruct::Base`. A 5-field `new` drops from 39 to 19 allocations. Values, errors and messages are unchanged. <!-- upgrading: none -->

### Documentation and tooling

- **UPGRADING.md: only silent changes need a Find on a green suite.** From a
  dry run against a large app: the TL;DR now lists the eight entries that change
  values or validity without raising, and says the other Finds cover code the suite
  doesn't reach. The base-10 Find matches whole literals only (849 hits → the real
  ones). The non-Hash Find is scoped to your struct classes, and the `dup` Find
  says when a hit matters. The RBS step names wrapper tasks, ripgrep's PCRE2 check
  comes first, and the effort estimate counts full suite runs. AGENTS.md and the
  skill follow.

## [0.14.0] - 2026-10-23

DST-aware zones and fuller array errors. `zone:` accepts IANA names
(`'America/Denver'`) and reads zone-less times at that zone's offset on that
date; a time in a spring-forward gap is refused, an overlap reads at the
daylight offset as ActiveSupport does. This adds `tzinfo` (`~> 2.0`) as a
runtime dependency, loaded only when a field names an IANA zone — Rails apps
already have it. Array errors now name every bad index, and `describe` lists
element options by name. See `UPGRADING.md` "0.13 → 0.14".

### Added

- **IANA names in `zone:`** on `:time` and `:datetime`: `optional :starts, :time, zone: 'America/Denver'`. A zone-less string is read as the wall clock in that zone *at that date* (`"2026-07-01 10:00"` → -06:00, `"2026-01-15 10:00"` → -07:00); a `format:` without `%z` likewise, an omitted date being today in the zone; a `Date` becomes midnight at that day's offset; an epoch under `format: '%s'` keeps its instant at the offset in force then. Input with its own offset (strings, `Time`, `DateTime`, TimeWithZone) keeps it, as with fixed offsets. A wall-clock time the zone skips (02:30 on a spring-forward day) is refused with a class-only message naming the zone; one it repeats (01:30 on a fall-back day) takes the daylight-time offset, as ActiveSupport's TimeWithZone does; a `Date` whose midnight is skipped becomes the day's first moment. The value is a plain `Time` / `DateTime` carrying the offset (not a `TZInfo::TimeWithOffset`). Validated at declaration through tzinfo: an unknown name, a no-`/` abbreviation or alias (`"MST"`, `"EST5EDT"`) and a Rails name (`"Mountain Time (US & Canada)"`, with a hint) raise `ArgumentError` naming the option; missing zone data raises saying to add `tzinfo-data`. Identical with and without ActiveSupport. `describe`, `Metadata#to_h` and the RBS are unchanged in shape. See USAGE "Zones".

### Breaking-ish (visible behaviour changes)

- **New runtime dependency: `tzinfo` (`~> 2.0`).** Apps without Rails gain `tzinfo` and `concurrent-ruby` in `Gemfile.lock`; a lock pinning tzinfo 1.x no longer resolves. It is required only when a field declares an IANA name, so `require 'field_struct'` and `"UTC"` / `"±HH:MM"` fields don't load it. <!-- upgrading: tzinfo-dependency -->
- **`zone:` no longer refuses IANA names, and its refusal message is reworded**: `zone: on Time expects an IANA name like "America/Denver", "UTC" or a UTC offset like "-06:00", got "MST". …` (was `… expects "UTC" or a UTC offset like "+00:00" or "-06:00", got … Zone names such as "America/Denver" are not accepted …`). <!-- upgrading: zone-accepts-iana-names -->
- **Array errors name every bad index, not only the first.** One bad element reads as before; several list their indexes and show the first one's reason: `could not be coerced: elements at index 1, 4 (index 1 shown): Integer fields expect …` for coercion (every `coercion_policy`, `:raise` included) and `elements at index 1, 4 are invalid` for `element:` validation. Past five indexes the rest are counted (`… 0, 1, 2, 3, 4 and 15 more …`). Indexes only, never values. An all-valid array costs the same as before. <!-- upgrading: array-every-index -->
- **`describe` lists an array's element options by name only**: `— element accepts in, base, strict` (was `— element accepts in (Array | Range), base (Integer), strict (TrueClass | FalseClass)`). The shapes are the element type's `option_schema`. <!-- upgrading: array-describe-names-only -->

### Documentation and tooling

- **The UPGRADING.md drift guard asks for a decision on every Changed / Removed bullet.** Each `[Unreleased]` bullet under `### Changed` or `### Removed` must carry a `<!-- upgrading: … -->` slug marker (with its UPGRADING.md entry) or `upgrading: none` (no caller action), so a visible change filed outside a Breaking heading can't skip the guide unnoticed. `none` never satisfies a Breaking bullet, and released sections are not re-checked. Convention in CLAUDE.md.

## [0.13.1] - 2026-10-22

Upgrade guidance, no code changes. `UPGRADING.md` walks a project from 0.10 to
0.13 step by step — symptom, an `rg` command to find the affected code, the fix
— for people and AI agents alike, and a spec keeps it in step with this
CHANGELOG.

### Documentation and tooling

- **`UPGRADING.md`: moving from 0.10 to 0.11, 0.12 and 0.13.** Every visible change as Symptom (the exception or failure you'll see) / Find (an `rg` command, each checked against a "before" snippet) / Fix (before/after) / Why, a symptom index, a straight 0.10 → 0.13 path, the opt-in options worth adopting, and how to bisect a failure by version. Its runnable fixes are doctested. AGENTS.md and the skill gain an "Upgrading" procedure for agents; the README links it from Installation; it ships in the gem. The skill's RBS example now shows the typed setter 0.12 generates.
- **Drift guard.** `spec/upgrading_spec.rb` fails when a CHANGELOG bullet under a Breaking heading (0.11.0 onward) has no `<!-- upgrading: … -->` marker, when a marked bullet has no UPGRADING.md entry with the same marker, when UPGRADING.md's covered range stops short of `VERSION`, or when it links a missing anchor. Breaking bullets since 0.11.0 now carry these invisible markers. Convention in CLAUDE.md.

## [0.13.0] - 2026-10-22

Safer input and log safety. Opt-in `strict: true` on `:string` / `:integer`;
error messages never echo a value and `sensitive: true` masks one in
`inspect`; `zone:` reads zone-less times at a declared offset; `with(**changes)`
copies with changes; array fields pass `element:` options to each element.
Defaults are unchanged except the Breaking-ish items below — message wording,
`:float` refusing hex strings, the element index in array errors, and `with` /
`dup` becoming reserved field names.

### Added

- **`strict: true` on `:string` and `:integer`** (opt-in, per field; defaults unchanged until 1.0). `optional :ref, :string, strict: true` accepts a String, Symbol, Integer or an object responding to `to_str`, and refuses a Hash, Array, boolean, Float/BigDecimal/Rational (whose `to_s` is `"0.12e2"`, `"1/2"`), Complex or any other object with a `TypeError` naming its class — by default those are stored as their `to_s` (`{a: 1}` → `"{a: 1}"`). `optional :cents, :integer, strict: true` accepts an Integer or a numeric equal to one (`12.0` → 12, `BigDecimal("12")`, `Rational(24, 2)`) and refuses `12.7` with an `ArgumentError` instead of truncating to 12; strings follow the default base-10 / `base:` rules unchanged, so `"12.0"` and `"1e3"` stay refused. Strict only narrows: an accepted value becomes exactly what the default would make of it. The string subtypes (`:immutable_string`, `:uuid`, `:url`, `:email`, `:binary`) inherit it. `strict:` must be a Boolean (`ArgumentError` at declaration otherwise) and raises on any other type, naming the types it applies to. See USAGE "Strict coercion".
- **`zone:` on `:time` and `:datetime`** (opt-in, per field; defaults unchanged). A zone-less string (`"2026-10-22 10:00"`) is read at the declared offset instead of the process zone (`:time`) or UTC (`:datetime`), so the same input is the same instant on any server: `optional :starts, :time, zone: '-06:00'`. Accepts `"UTC"` and fixed `"±HH:MM"` offsets; IANA names (`"America/Denver"`), `"Z"`, `"utc"` and colon-less offsets raise `ArgumentError` at declaration — the stdlib has no zone database and acceptance must not depend on ActiveSupport being loaded. It only fills a *missing* offset: a string with an offset, a `Time`, `DateTime` or TimeWithZone keeps its own; a `Date` becomes midnight in the zone; a `format:` without `%z` (`:db`, `'%H:%M'`) is read in the zone, filling an omitted date from today in that zone, and an epoch string under `format: '%s'` keeps its instant at that offset; a string naming a zone the stdlib cannot read (`"… XYZ"`) is refused rather than overridden; Integers stay refused. Shown in `describe` and `Metadata#to_h` like any option. See USAGE "Zones".
- **`Base#with(**changes)`** returns a new instance of the receiver's class with the given attributes changed, leaving the receiver untouched (like `Data#with`). Changed fields run the setter pipeline (coercion, `coercion_policy`, errors rewritten) and cross-field validators rerun; unchanged fields, their errors included, are carried over as `dup` carries them, and callable defaults are not called again. Shallow, like `dup`: unchanged nested structs and arrays are shared. Unknown keys follow `unknown_attributes`. Works on `immutable!` and frozen instances; the copy is immutable when the class is and frozen when the receiver is. Positional arguments raise `ArgumentError`. See USAGE "Copying with changes".
- **`element:` on `:array` fields** passes the element type's own options to every element: `optional :ids, :array, of: :integer, element: {strict: true, base: 16}`. Coercion options (`strict:`, `base:`, `round:`, `format:`, `zone:`, `values:`) apply to each element's coerce; validation options (`format:` Regexp, `enum:`, `in:`) are checked per non-nil element, and a breach is reported by index (`"element at index 2 is invalid"`). Checked at declaration against the element type's schema with the error a scalar field would get, prefixed `in element: of array field :ids, …`; unlike a field, `element:` refuses keys its element type doesn't take (listing the ones it does) and field-level options (`required:`, `sensitive:`, …). A temporal element's `format:` is what `to_json` writes, so `from_json` round-trips. Shown in `Field#inspect`, `Metadata#to_h` and `describe`, which also lists what each array's elements accept. Not supported for arrays of arrays or nested-struct elements. Generated RBS is unchanged (no element option changes an element's class). See USAGE "Element options".
- **`sensitive: true` field option** (any type). `Base#inspect` — and so `pp`, the `errors:` suffix of an invalid instance, and nested structs/arrays of them — renders `[FILTERED]` (`FieldStruct::FILTERED`) in place of a non-nil value; `nil` still shows. Data paths are deliberately **not** masked: the reader, `attributes`/`to_h`, `as_json`/`to_json`, `deconstruct_keys` and equality return the real value, so `from_json(to_json)` still round-trips. Must be `true`/`false` (`ArgumentError` at declaration otherwise). Readable as `Field#sensitive?`; shown in `Field#inspect`, `Metadata#to_h` (`sensitive: true`) and `describe` only when set; kept out of `Field#options`. See USAGE "Log safety".

### Documentation and tooling

- **USAGE: "Payment and API boundaries"** — when and why to declare `unknown_attributes :raise` (on every struct that reads input; nested classes don't inherit it from their holder; `from_json` reverse-maps `serialize :json` names first). Doctested.
- **USAGE: "Validity is computed on assignment"** — mutating a nested struct or array element in place doesn't refresh the parent's errors (stale in both directions), and an in-place array push skips coercion; re-assign the field or use `with`. Doctested. README, AGENTS.md, the skill and getting started now cover `strict:`, `zone:`, `sensitive:`, `element:`, `with` and this.
- **`benchmarks/run.rb` and `rake bench`** (not in the default task): dependency-free timings for `new`, `from_json`, `to_json`, nested, a 100-element array, `strict:` vs default and a validation-heavy struct. README "Performance" has indicative numbers. `benchmarks/` is left out of the packaged gem.

### Breaking-ish (visible behaviour changes)

- **`field :with` and `field :dup` are refused at declaration** (added to `FieldStruct::Base::RESERVED_FIELD_NAMES`): `with` is now a `Base` method, and `with` relies on `dup`. A field of either name would shadow it. Rename the field; `serialize :json, with_field: 'with'` keeps the external key. `Scaffold` renames them with a `_field` suffix. <!-- upgrading: reserved-with-dup -->
- **A refused array element is named by its index.** Every `:array` coercion failure is prefixed with the element's 0-based index, keeping the element type's error class: `could not be coerced: Integer fields expect …` → `could not be coerced: element at index 1: Integer fields expect …` (and so in `CoercionError` under `:raise`). `describe` lines for `:array` fields gain an `element accepts …` part, and an array field's `options` list `of_type:` first. <!-- upgrading: array-element-index -->
- **No error message echoes an input value** (payments data must not reach logs). Messages now name the field, the expected type and the input's class. If you match on message text, update the patterns: <!-- upgrading: messages-never-echo-values -->
  - `:boolean`: `cannot coerce "maybe" to boolean` → `Boolean fields expect true, false, 1, 0 or one of the strings "true", "1", "false", "0", got a String that is not one` (non-Strings: `…, got Hash`). A `values:` vocabulary is listed instead of the defaults.
  - `:union`: `no union member could coerce "abc"` → `no union member (Integer | Boolean) could coerce String input`.
  - `coercion_policy :raise`: `could not coerce "abc" for cents: …` → `could not coerce String input for cents: …`.
  - `from_json` with a non-object root: `…, got Array: ["x"]` → `…, got Array`. Invalid JSON keeps Oj's error class (`EncodingError`) but its message is now `from_json could not parse its input as JSON (unexpected character at line 1, column 7)` — Oj's own message quoted the whole input. The Oj error is no longer the `cause`.
  - `:integer` / `:float` / `:decimal` messages were already class-only, but the Kernel conversion error (`invalid value for Integer(): "…"`) rode along as the exception's `cause`, which error reporters print. It is dropped.

- **`:float` refuses hex strings.** `"0x1A"` was read as 26.0 (`Kernel.Float` accepts hex) while `:integer` has refused it since 0.11; both are now base 10. A hex string — with or without sign or surrounding whitespace, including hex-float `"0x1p3"` — is an ordinary coercion failure (`Float fields expect a base-10 number, got a String that is not one`). Binary/octal prefixes were already refused; `"1_000.5"`, `" 2.5 "`, `"1e3"`, `".5"` and `"017"` (→ 17.0) read as before. <!-- upgrading: float-refuses-hex -->

## [0.12.0] - 2026-10-22

Valid, guarded RBS. The gem's own signatures go from 215 `untyped` to 5 and
can only get more typed (CI ratchet); generated RBS for your structs carries
real element types, typed setters and an `rbs_type:` escape hatch. No runtime
behaviour changes beyond `rbs_type:` becoming a recognized option.

### Added

- **`rbs_type:` field option.** `optional :scope, :value, rbs_type: '::ActiveRecord::Relation'` makes `FieldStruct::RBS` emit that type for the field's reader and writer instead of the derived one. Signatures only — no effect on coercion or validation. Must be a non-blank String (`ArgumentError` at declaration otherwise); it is not parsed, since `rbs` is not a runtime dependency. Readable as `Field#rbs_type` and shown in `Field#inspect`; kept out of `Field#options`. <!-- upgrading: rbs-type-option -->
- **`Types::Base#rbs_type` hook.** A custom type can return an RBS expression (`def rbs_type = '::Hash[::Symbol, ::String]'`) for every field of that type. Default `nil` (derive from `ruby_type`). A field's `rbs_type:` wins over it.
- **`FieldStruct::RBS.type_for(field, nullable: nil) -> String`.** The per-field RBS type, exactly as `generate` emits it, for other generators. `nullable: nil` follows `!field.required?`.

### Changed

**Generated RBS changes for consumers.** Regenerating sigs for your own structs with `FieldStruct::RBS.generate` gives different output, and Steep may report new errors in code that relied on the old `untyped` writers:

- **Writers are typed `(T? value) -> T?`** (were `(untyped value) -> untyped`). The runtime setter accepts `nil` and returns the coerced value. Assigning loose input the type would coerce (`user.age = "30"`) still works in Ruby but is now a Steep error. <!-- upgrading: rbs-typed-writers -->
- **Output opens with a comment header** saying the types describe a *valid* instance — an invalid one (unset required field, `:keep_raw` failure holding raw input) can hold other values. <!-- upgrading: rbs-header -->
- **Array elements of a scalar type are nullable** (`of: :string` → `::Array[::String?]`): `["x", nil]` passes validation, so the old `::Array[::String]` was false. Nested elements stay non-nil (a nil one fails validation). A union's members use their own `rbs_type`, and an anonymous nested class raises `ArgumentError` instead of emitting `::?`. <!-- upgrading: rbs-nullable-array-elements -->
- **Generic arguments are always present.** A custom type whose `ruby_type` is a bare generic class (`::Hash`, `::Array`, `::Range`) emits `::Hash[untyped, untyped]` and so on, instead of a bare `::Hash`, which `rbs validate` rejects. <!-- upgrading: rbs-generic-arguments -->
- **Unions render a boolean member as `bool`** (`(::String | bool)`, was `(::String | ::TrueClass | ::FalseClass)`), and a union with a `:value` member collapses to `untyped`. <!-- upgrading: rbs-union-bool -->
- **Optional `:value` fields are `untyped`, not `untyped?`.** <!-- upgrading: rbs-optional-value-untyped -->

### Signatures

- **Nil is admitted where the runtime returns it.** `Base#attributes`, `#to_h`, `#as_json` and `#deconstruct_keys` return `::Hash[Symbol, Object?]`, `#deconstruct` `::Array[Object?]`, `Field#options` is `::Hash[Symbol, Object?]` (e.g. `format: nil`), and `Metadata#to_h` is `::Hash[Symbol, ::Hash[Symbol, Object?]]` (`default: nil`, `description: nil`). They claimed non-nil values. No runtime change. Steep report-only count 190 → 189. <!-- upgrading: own-sigs-admit-nil -->

- **Core types in `Types` name the core class.** `Types::String#coerce`, `Types::Symbol#coerce`, `Types::Integer#coerce` and `Types::Float#coerce` were typed with bare `String` / `Symbol` / `Integer` / `Float`, which RBS resolves to `FieldStruct::Types::String` etc. inside `module Types`. Their YARD now says `::String` and friends, so the sig says the value is a `::String`, not a type object.
- **Keyword and rest splats are typed per value.** `**options` on `field` / `required` / `optional` / `Field.new` is `**Object` (was `**::Hash[Symbol, Object]`, which meant every option value had to be a Hash), `serialize`'s `**mapping` is `**(String | Symbol)`, and `validate`'s `*method_names` is `*Symbol` (was `*::Array[Symbol]`). No runtime change. `sigs:untyped` ceiling 215 → 212, sord allowlist 155 → 152.
- **Private helpers, generics and constants are typed.** Every private helper Sord used to write as `(untyped ...) -> untyped` now has YARD types, generic `Hash[untyped, untyped]` / `Array[untyped]` name their key and element types, and Sord runs without `--skip-constants`, so the sig declares the gem's constants (`VERSION: String`, `Base::RESERVED_FIELD_NAMES: ::Array[Symbol]`, …) from their `@return` tags. RBS has no private constants, so `private_constant`s (`Base::UNSET`, `Metadata::EMPTY_SERIALIZATION`, …) are declared too. Where a value really is anything (raw input, `:value` fields, Oj output) the type is `Object?`, never narrower. Hashes whose values can be `nil` now say so: `new` / `assign_attributes` take `::Hash[(Symbol | String), Object?]`, and the `**options` of `field` / `required` / `optional` / `Field.new` are `**Object?` (FS-6 made them `**Object`, which rejected `format: nil`). `Base.validators` is `::Array[Proc]` (it only ever holds lambdas and blocks). No runtime change. `sigs:untyped` ceiling 212 → 5, sord allowlist 152 → 6; what remains is `#to_hash` input (`_ToHash[untyped, untyped]`) and `Field#default`, a value or a callable.

- **`sig/` can only get more typed.** Three guards, no Steep gate:
  - `rake sigs:untyped` (CI, `release:check`) counts non-comment `untyped` in `sig/` against a committed ceiling (`rakelib/sig_guards/untyped_ceiling.txt`, 215). Above it fails; below it also fails until the ceiling is lowered, so the slack can't be spent later.
  - `sigs:generate` / `sigs:check` fail on a Sord `[OMIT]` / `[DUCK]` warning missing from `rakelib/sig_guards/sord_allowlist.txt` (155 entries, keyed without file:line), and on an entry Sord no longer emits, so the list only shrinks.
  - `sigs:validate` runs `rbs validate` over the whole `sig/` directory, not just the generated file.
- **Sord runs without `--replace-errors-with-untyped`.** The output is byte-identical today; an unresolvable YARD type now lands in the sig as its own name (which `rbs validate` rejects) instead of a quiet `untyped`, on top of the existing generation-time guard.
- **Report-only Steep lane.** A `types` job on Ruby 3.4 runs `steep check` (Steep 2.1 / rbs 4.2 via `gemfiles/types.gemfile`, since both need Ruby >= 3.3) and prints the problem count. It never fails the build and is not part of the required `ci` check.
- **The packaged gem also leaves out `gemfiles/`** (CI-only Gemfiles).

## [0.11.0] - 2026-10-22

Correctness and safer input. A number field holds a finite number of its own
type, read the same way regardless of how the host process is configured;
`from_json` reads decimals exactly; input that isn't a Hash, and field names
`Base` relies on, are refused up front.

### Breaking-ish (visible behaviour changes)

- **`:integer` strings parse in base 10.** `Kernel#Integer` with no radix honours Ruby literal prefixes, so `"010"` became 8 and `"0x1A"` / `"0b11"` were accepted as hex and binary. Now `"010"` is 10, `"007"` is 7, and prefixed strings are refused. Whitespace and digit underscores still parse (`" 42 "`, `"1_000"`). Floats still truncate; Integers pass through. <!-- upgrading: integer-base-10 -->
- **`round: 0` returns a `BigDecimal` / `Float`, not an `Integer`.** `:decimal` and `:float` fields with `round: 0` used to hold an Integer; they now keep the field's type (`BigDecimal('4')`, `4.0`). <!-- upgrading: round-zero-keeps-type -->
- **`:decimal` rounding ignores the global `BigDecimal.mode`.** It followed the process-wide rounding mode, so a host calling `BigDecimal.mode(BigDecimal::ROUND_MODE, :banker)` turned `12.345` at `round: 2` into `12.34`. Rounding is now pinned half up (ties away from zero) per call, for `:float` too. <!-- upgrading: decimal-rounding-ignores-mode -->
- **NaN and ±Infinity are refused.** `:float` and `:decimal` stored them as valid values (`:decimal` accepted `"NaN"` and emitted `"NaN"` in JSON); `:integer` raised `FloatDomainError` out of `.new` and `from_json('{"n": 1e400}')`. All three now treat a non-finite value — Float, BigDecimal, String or JSON `1e400` — as an ordinary coercion failure under the field's `coercion_policy`. A `:union` refuses a non-finite Float or BigDecimal outright, before any member sees it, so `of: [:integer, :string]` no longer falls through to storing `"NaN"` / `"Infinity"` as a valid String. <!-- upgrading: non-finite-refused -->
- **`:integer`, `:float` and `:decimal` coercion messages name the input class, never the value.** That covers the new non-finite refusals and the parse failures these types re-raise from `Kernel#Integer` / `#Float` / `#BigDecimal`, whose own messages echoed the input (`invalid value for Float(): "NaN"`, a Rational's `"1/3"`). It is not yet true everywhere: the field error a `:union` records when no member matches, and the `CoercionError` raised under `coercion_policy :raise`, still include the raw value. <!-- upgrading: numeric-messages-name-class -->
- **`new` and `assign_attributes` refuse input that isn't a Hash.** Anything that is not a Hash and does not respond to `to_hash` raises `ArgumentError` naming its class (`Person.new expects a Hash (or an object responding to #to_hash), got Array`). **Breaking:** an array of pairs (`new([[:name, "Ann"]])`) used to work and now raises; pass `pairs.to_h`, as ActiveModel's `assign_attributes` also requires. `new([])` used to build an empty instance silently, and `new("x")` / `new(5)` raised `NoMethodError`. Objects responding to `to_hash` are converted first, so a permitted `ActionController::Parameters` keeps working — an *unpermitted* one now raises Rails' own `UnfilteredParameters` instead of being read key by key. `new(nil)` is now the same as `new` (it raised `NoMethodError`); `assign_attributes(nil)` raises `ArgumentError`, as ActiveModel's does. <!-- upgrading: non-hash-input-refused -->
- **Field names `Base` relies on are refused at declaration.** `field :errors` raised a `NoMethodError` from deep inside the class body, `field :class` likewise, and `field :hash` / `field :attributes` were accepted but silently broke equality, `inspect` and validation by shadowing the methods `Base` calls on itself. These names (`FieldStruct::Base::RESERVED_FIELD_NAMES`: `errors`, `attributes`, `hash`, `class`, `send`, `to_h`, `inspect`, `as_json`, `raise`, … and `Base`'s private helpers) now raise `ArgumentError` naming the field and suggesting a `serialize :json` mapping. The list is curated, not `instance_methods`: `method`, `name` and `type` stay legal. `Scaffold` renames the same names with a `_field` suffix. <!-- upgrading: reserved-field-names -->
- **`from_json` parses JSON decimals as `BigDecimal`, not Float.** It parsed with Oj's default, so `{"d": 1234567890123.4567}` reached a `:decimal` field as `1234567890123.46` — rounded through a Float before the field ever saw it. Numbers with a fraction or exponent now parse as `BigDecimal` (`decimal_class: BigDecimal`), so `:decimal` gets the exact digits. Visible elsewhere: <!-- upgrading: from-json-bigdecimal -->
  - `:float` fields are unchanged (still a Float). `:integer` fields still truncate (`3.7` → `3`).
  - **`:value` fields, and numbers inside a `:value` Hash or Array, now receive `BigDecimal` instead of `Float`** — and since `to_json` writes a `BigDecimal` as a string, a `:value` that passed `2.25` through now emits `"2.25"`.
  - JSON `1e400` is now a finite number rather than a Float overflowing to Infinity: a `:decimal` field reads it exactly (as it already read the String `"1e400"`), an `:integer` field reads it as `10**400`, and a `:float` field still refuses it.
  - An `:integer` field refuses a decimal whose integer part has more than 4300 digits (`Types::Integer::MAX_DECIMAL_DIGITS`, Python's CVE-2020-10735 limit). Without it, JSON `1e10000000` (18 bytes) built a 33-million-bit Integer in seconds of CPU.
  - The `oj` dependency floor rises from `>= 3.0` to `>= 3.11.2`, the release that fixed the `decimal_class` option; an older Oj would ignore it and quietly keep the Float. <!-- upgrading: oj-floor -->
- **`base:` is now a reserved option name, like `round:`.** FieldStruct treats every option some registered type declares as its own. So a custom type that reads `base:` from its `coerce` kwargs without declaring it in `own_option_schema` used to receive it as a pass-through option (`optional :x, :my_type, base: 16` worked), and now raises at declaration: `base: option does not apply to MyType fields. It applies to: Integer.` That is how `round:` already behaves. The fix is to declare it: `def self.own_option_schema = {base: option(type: [::Integer])}`. For the same reason, a foreign `base:` on any other built-in type (e.g. `optional :code, :string, base: 16`, kept as metadata for downstream tooling) now raises instead of being stored on the Field. <!-- upgrading: base-reserved-option -->

### Added

- **`base:` option on `:integer`** — an Integer radix (2..36, checked at class load) for string input: `field :code, :integer, base: 16` reads `"1A"` as 26. `base:` on any other type raises at declaration, naming `Integer`.

### Fixed

- **`dup` and `clone` give the copy its own `errors`.** The copy shared the original's `Errors` object, so `b = a.dup; b.name = ''` made `a.valid?` false too. The copy now starts with a copy of the original's messages and owns them; `clone` of a `frozen!` instance stays frozen, and `clone(freeze: false)` / `dup` give an independent mutable copy. The copy is still shallow: a nested struct is shared, so mutating `b.address` changes `a.address` too. <!-- upgrading: dup-own-errors -->
- **`Scaffold.from_json` output evaluates when keys need renaming.** It emitted `serialize :json, first_name: "firstName"` *before* the field lines, and `serialize` refuses undeclared fields, so the generated class raised `ArgumentError` the moment it was loaded. The mapping now follows the fields. Keys that normalize to the same name (`fooBar` and `foo_bar`, or `errors` and `errors_field`) get distinct fields (`foo_bar2`) instead of one silently overwriting the other.
- **`from_json` reverse-maps `serialize :json` names for struct members of a `:union`.** It reverse-mapped nested structs and arrays of them, but handed a union's object over with its external keys, so a struct member saw `{"cardNumber" => ...}` instead of `card_number:` and `Payment.from_json(payment.to_json)` came back invalid — breaking the README's round-trip promise. Members are now tried in declared order, as the union's own coercion does, with each struct member reverse-mapping through its own mapping; the first that accepts the object wins.
- **The field setter treats `RangeError` as a coercion failure.** `FloatDomainError` (one of its subclasses) and Complex-to-real conversion (`Complex(1, 2)` into `:integer` or `:float`) used to raise out of `.new`; they are now handled by `coercion_policy`, including when a custom type raises them. <!-- upgrading: range-error-policy -->

### Docs

- **README corrections** (#8): `in:` with a Range is a bounds check via `cover?`,
  and `:iso8601` round-trips as RFC 3339 rather than via `strptime`/`strftime`.
- **Install from GitHub.** The README installs from a release tag; the gem is
  not on RubyGems yet.

### Tooling / CI

- **Ruby 4.0 lane and one aggregate `ci` check.** The full battery now also
  runs on Ruby 4.0, and a `ci` job passes only when every job passed;
  `main` and `develop` require it.
- **The packaged gem leaves out contributor-only files** (`.claude/`,
  `.claude-plugin/`, `CLAUDE.md`, `docs/origin/`, build and lint config).
- **The commit guard recognizes `git commit` by its command text** (#7).

## [0.10.0] - 2026-09-03

Temporal types: one behaviour whether or not ActiveSupport is loaded, a
declared format that actually constrains, and an `iso8601` preset that means
RFC 3339.

The through-line is a single failure mode — **a wrong answer delivered
confidently**. A `:time` field accepted `"not-a-time"` as valid-nil under Rails,
read `2026-06-31` as 1 July everywhere, and a declared `format:` refused nothing
it was given. Each of those returned a value rather than an error, which is the
one outcome a caller cannot detect.

### Breaking-ish (behaviour changes; no consumer declares a temporal field today)

- A blank string is a coercion failure for all three temporal types.
- A value that is neither a String nor a temporal object is refused.
- A declared `format:` anchors — trailing junk is refused.
- `:time` refuses a day that never existed, as `:date` and `:datetime` already did.
- With no declared format, a string must name a whole day.
- `format: :iso8601` is RFC 3339 in and out; its output is `Z`/`+HH:MM`, not `+0000`.

### Changed

- **`describe` now shows what a field declares, not only what its type accepts.** It rendered the *type's* option vocabulary and nothing else, so a field declaring `format: :iso8601, enum: %w[USD EUR]` printed identically to one declaring nothing at all — the schema belongs to the type, and the declaration belongs to the field. Both are now on the line, declaration first:

  ```
  on (Date, required) — format: :iso8601 — accepts format (String | Symbol; presets: iso8601, us, eu), in (Array | Range)
  ```

  Options left at `nil` are omitted, so a temporal field with no declared format does not advertise the `format: nil` that `apply_default_format` puts there internally.


- **The `:iso8601` preset is now RFC 3339, in and out.** It was a strftime string, and that had it emitting a value its own documented format would reject: `%z` renders `+0000`, while RFC 3339 — which is what JSON Schema's `date-time` means — requires `+00:00` or `Z`. It also refused fractional seconds, which most JSON APIs emit, because no strftime string can express "optional fractional seconds".

  FieldStruct now parses and renders the preset itself, via `Types::Rfc3339Format`. It is deliberately **not** `Time.iso8601` / `DateTime.iso8601`: those two disagree with each other on nearly every edge, and `Time.iso8601('2026-02-30T10:30:00Z')` returns **2 March** — the same silently-wrong-day defect this release exists to remove. A `:time` field and a `:datetime` field declaring the same preset now accept exactly the same strings, which was not previously true.

  Accepted: full-width fields, `T` separator, whole seconds, optional fractional seconds, and a mandatory offset (`Z` or `±hh:mm`; `±hhmm` too, since that is what v0.9.0 emitted, so its own output still parses). Refused: a missing offset, a space separator, missing seconds, week and ordinal dates, the basic unseparated form, five-digit or signed years, hour 24, second 60, an impossible UTC offset, and any date that never existed. Output is `Z` for UTC and `+HH:MM` otherwise, with fractional seconds only when the value carries them.

  **This is what lets a caller stop hand-rolling the contract.** `required :on, :date, format: :iso8601` now accepts and refuses exactly what `required :on, :string, format: /\A\d{4}-\d{2}-\d{2}\z/` plus a `Date.iso8601` validator does — verified input by input. The other presets (`:us`, `:eu`, `:db`, `:rfc2822`) are display and interchange formats rather than wire contracts, so they stay strftime-based; they still get anchoring and civil-date validity.

- **A declared `format:` now anchors, and every temporal type refuses a day that never existed.** Three rules the stdlib parsers left to their caller, each one a case where the stdlib answers a question it was not asked:
  - **Anchoring.** `strptime` matches a *prefix* and discards the rest, so `Date.strptime('2026-07-031', '%Y-%m-%d')` returned the 3rd and threw the trailing `1` away, and `'2026-07-03T10:30:00+0000-NONSENSE'` parsed clean under the `iso8601` preset. A string with characters left over is now refused. **"Anchor" means trailing-junk rejection and nothing more** — widths, sign and case stay strptime-lenient for a hand-written format, because `%m` accepting one or two digits is strptime's contract rather than a defect.
  - **Civil validity.** `Date` and `DateTime` already refused the 30th of February. **`:time` did not** — `Time.parse`, `Time.strptime` and `Time.new` all roll it forward to 2 March silently, so `required :at, :time` read `"2026-06-31 10:30:00"` as 1 July and reported the struct valid, in *both* lanes. All three types now refuse it.
  - **Completeness.** With no declared format the stdlib parsers fill in what the string omits, from *today*: `Time.parse('10:30')` is today at 10:30, `'July'` is the 1st of July this year, `'12'` is the 12th of this month. A value whose meaning depends on when it was parsed is not a value, so a string with no declared format must now name a whole day. A *declared* format that names only part of one (`format: '%H:%M'`) is a deliberate choice and still works.

  This does not make `Date.parse` strict about what counts as a day — `'v1.2.3'` still reads as 2001-02-03, because `Date._parse` finds `1.2.3` and all three components are present. The no-format path delegates to the stdlib by design; a caller who needs a narrow contract declares a format.

- **A declared `format:` is kept exactly as written.** `format: :iso8601` used to be overwritten at declaration time with the strftime String it expands to, so `metadata.to_h[:at][:options][:format]` reported `"%Y-%m-%dT%H:%M:%S%z"` and the preset *name* — the one fact a documentation or schema generator actually wants — was gone. Recovering it by reverse-mapping the String back to a name worked only while no two presets shared a value: luck, not a contract. The declaration now survives (`:iso8601` stays `:iso8601`, a hand-written String stays that String) and resolution to a strftime format happens at coerce and render time instead, via the new `Types::Base.resolve_format` and `TimeFormatResolver.resolve`. Parsing, serialization and round-tripping are unchanged; an unknown preset name still raises at declaration, not at first use.

### Fixed

- **`in:` with a Range is a bounds check again.** Validation asked `Range#include?`, which *enumerates* a non-numeric range instead of comparing endpoints. For a `Date` range that was only wasteful — 365 successor steps to answer one comparison. For a **`DateTime` range it was wrong**: the range steps by whole days, so any value not landing exactly on midnight was reported invalid inside a range that plainly contained it. `(DateTime.new(2026,1,1)..DateTime.new(2026,12,31)).include?(DateTime.new(2026,7,3,10,30))` is `false`; `cover?` is `true`. Ranges now use `cover?`; an `Array` remains a membership test. No string-range behaviour changes, because the DSL refuses `in:` on String fields outright.

- **Temporal coercion no longer depends on whether ActiveSupport is loaded.** `Date`, `Time` and `DateTime` dispatched on `respond_to?(:to_date)` / `:to_time` / `:to_datetime` — predicates ActiveSupport adds to every core class, so the types took one branch in their own suite and a different one under Rails. Three defects followed, all measured on v0.9.0 under Rails 7.2:
  - **`:time` accepted garbage as valid.** `optional :t, :time` given `"not-a-time"`, `"tomorrow at noon"` or `""` was **valid with a nil value**, because AS's `String#to_time` returns `nil` rather than raising. On plain Ruby all three were invalid.
  - **Blank strings diverged.** `""` and `"  "` were valid-nil under Rails and a coercion failure on plain Ruby.
  - **Two-digit years diverged.** `"03 Jul 26"` was year **0026** under Rails (AS passes `comp=false` to `Date.parse`) and 2026 on plain Ruby.

  Coercion now dispatches on explicit stdlib classes — `String`, then `DateTime` (before `Date`, being its subclass), then `Date`, then `Time` — and parses through `Date.parse` / `Time.parse` / `DateTime.parse` / `strptime`, none of which ActiveSupport redefines. Cross-class conversion is built from components rather than `to_time` / `to_datetime`, which ActiveSupport *does* redefine: under AS 7.2 `DateTime#to_time` shifts to the system-local zone and emits a deprecation warning, while 8.x preserves the offset. Building from parts yields the same instant and the same offset with no ActiveSupport, with 7.2, and with 8.x.

  Two behaviour changes fall out, both of which restore the plain-Ruby answer: **a blank string is now a coercion failure** for all three types (as it already was for `:integer`, `:float`, `:big_decimal` and `:boolean` — only `:string` treats blank as missing), and **a value that is neither a String nor a temporal object is now refused** rather than run through `parse(value.to_s)`, which invented data: `Time.parse('[2026, 7, 3]')` returned *now*, `'v1.2.3'` read as 2001-02-03, and the Integer `20260703` parsed as a valid Date. That arm was already inconsistent — with a format declared, `:date` refused the Integer while `:time` accepted it.

- **`Date` now honours `format:` when parsing a String, as documented and as `DateTime` and `Time` already did.** `Types::Date#coerce` converted anything responding to `to_date` *before* consulting the format, which made the `strptime` branch unreachable for the exact input it exists for. ActiveSupport defines `String#to_date`, so **under Rails every string was parsed by `Date.parse` and the declared format was silently ignored** — an ambiguous date such as `07/03/2026` under `format: '%Y-%m-%d'` was accepted and read as 7 March instead of being refused. Plain Ruby has no `String#to_date`, which is why the type's own specs never took that branch and the defect survived. The `String`-with-`format` check now comes first, matching `DateTime` and `Time`; a non-string still converts through `to_date`, since a format describes how a *string* is read.

### Tooling / CI

- **New ActiveSupport lane.** The suite now also runs against a host that has loaded ActiveSupport, on **7.2 and 8.1 pinned separately** (they differ on `to_time_preserves_timezone`, which changes what `DateTime#to_time` returns). Dev dependency only — the gemspec is untouched. The lane runs under a **non-UTC `TZ`** on purpose: two of the defects it exists to catch involve the process zone and one of them does not reproduce under `TZ=UTC`, so a UTC-only lane would hide a bug it was added to find. It also **raises on ActiveSupport deprecations** rather than warning, so code reaching for a deprecated conversion fails loudly instead of quietly returning the wrong zone. Set `FIELD_STRUCT_ACTIVESUPPORT=1` with `BUNDLE_GEMFILE=gemfiles/activesupport_7_2.gemfile` (or `_8_1`) to run it locally. This lane is the reason the defects above are now visible: without it, the gem's suite could only ever test the half of the world that does not load Rails.

- **Static guardrail against framework-redefinable dispatch.** `spec/guardrails_spec.rb` now fails if anything in `lib/` calls `respond_to?` with a predicate ActiveSupport defines or redefines on core classes (`to_date`, `to_time`, `to_datetime`, `as_json`, `blank?`, `try`, …), naming the offending file and line. One documented exception is allowlisted: `Base#json_value`'s terminal `as_json` arm, which is reached only for `:value`-typed fields and where the ActiveSupport outcome is the better one (a Struct serializes as `{"x":1,"y":2}` rather than `"#<struct ...>"`). The guard runs in milliseconds and catches a new probe at PR time; it does **not** replace the ActiveSupport lane, because AS changes semantics and not merely which predicates answer true.

## [0.9.0] - 2026-06-03

Discoverability and toolchain hardening on top of v0.8.0's legibility work.

### Added

- **`FieldStruct::Base.describe` / `Metadata#describe`** — a human/agent-readable schema summary: one line per field with its type, required-ness, and the native options that field's type accepts (value shapes, required options starred, presets listed). The readable companion to the structured `metadata.to_h` — answers "what does this model look like, and what can I put where" in one call.
- **`Types::Base.own_option_schema`** — the per-type hook for declaring a type's own options; `option_schema` merges it down the class chain.

### Changed

- **`Types#option_schema` is frozen and memoized per type class.** A type's option vocabulary is fixed at load, so the inheritance merge is computed once instead of on every field declaration. Types now declare `own_option_schema` instead of `super.merge(...)`; the public `option_schema` return value is unchanged.

### Documentation

- **YARD coverage to 100%** — documented the remaining constants, the `FieldStruct` / `FieldStruct::Types` modules, the per-type `resolve_options` overrides, `PresetResolver.call`, and the internal `inherited` / `canonicalize_serialized_value` hooks.
- README now surfaces `errors.full_messages`, the invalid-instance `inspect` output, and runtime option discovery (`Type.option_schema`) — the v0.8.0 surfaces that only `USAGE.md` / `AGENTS.md` had documented.

### Tooling / CI

- **Sord-warning guard.** `sigs:generate` now fails when Sord can't resolve a YARD type and silently falls back to `untyped` — a degradation that was invisible to `sigs:check` (the committed file already carried the `untyped`). The usual cause is a bare stdlib name (`Symbol` / `Array`) colliding with `Types::Symbol` / `Types::Array`; the fix is to fully-qualify it. The affected `option_schema` annotations were qualified accordingly.
- **CI matrix widened** from a single Ruby (3.3.6) to **3.2 / 3.3 / 3.4** (full battery), plus a new **Ruby-floor job** that runs the library specs on **3.0 / 3.1** via a minimal `gemfiles/floor.gemfile` (no dev toolchain — `rbs`/`sord` need Ruby ≥3.2), proving the gem's advertised `>= 3.0` runtime floor. The one rbs-grammar spec self-skips where the gem is absent.

## [0.8.0] - 2026-06-03

Legibility for humans and agents, made a first-class design invariant and
delivered across the error, inspection, and option surfaces.

### Added

- **`FieldStruct::Errors#full_messages`** — renders each validation message as a complete sentence by prepending the humanized field name (`first_name` + `is required` → `"First name is required"`). Humanization is deliberately minimal (underscores to spaces, first character upcased — no inflector, no `_id` stripping, no i18n), so the transform stays predictable. Messages on `:base` (the cross-field convention) pass through unprefixed.
- **`Types::Base.option_schema`** — every type now declares its native field options in one place, as a frozen `{name => {type:, required:, presets:}}` hash, inherited via `super.merge` so subtypes pick up their parent's options (`:uuid` inherits `:string`'s `format:` / `enum:`). The type system can now answer "what options do I accept, of what shape, with what presets" at runtime, for both humans and agents, without reading source.
- **`Registry#type_classes`** — enumerates every distinct type class resolvable through the registry (local plus parent chain), backing the reserved-option-name computation and general discoverability.

### Changed

- **Field-option validation is now schema-driven and three-way** (validate-native, pass-through-foreign), replacing the scattered `format:`/`enum:`/`in:` applicability checks. A native option with a wrong-shaped value (`round: '2'`) raises at class load naming the expected shape; a known option used on the wrong type (`enum:` on `:integer`, a misplaced `of:`) raises naming the types it *does* apply to; an unknown option is left untouched on the `Field` so downstream tooling (e.g. an Avro schema exporter) can carry its own options. The wrong-family error *messages* changed (e.g. "enum: option does not apply to Integer fields. It applies to: String, Symbol.").
- **`Base#inspect` surfaces validity.** An invalid instance now appends its per-field errors — `#<User name: "" age: 30 errors: {name: ["is required"]}>` — so the most-read debug output no longer hides invalidity. Valid instances are unchanged, byte for byte. `inspect` reads the current errors and never re-runs validation, so printing an instance can't mutate it.

### Documentation

- Named **legibility for humans and agents** as design invariant 7 in `.claude/project_intent.md`, phrased operationally (the public surface must explain itself without source). Reconciled the source-of-truth docs with reality: `docs/origin/plan.md` is now framed as the frozen design-rationale record, `project_intent.md` carries a current Capabilities section, and `CLAUDE.md` re-points "source of truth" (current behavior → `USAGE.md`/`README.md`; rationale → `plan.md`). `USAGE.md` / `AGENTS.md` document the new runtime option discoverability and the inspect/error surfaces.

## [0.7.1] - 2026-05-28

Documentation: an adoption guide, an agent router, and clearer inheritance semantics.

### Added

- **`docs/getting_started.md`** — a getting-started / integration guide (general Ruby plus a Rails section) with a task→API map, an error→meaning→fix table, a worked end-to-end example, common mistakes, and an "agent toolbox". Its general-Ruby examples are executed by the doctest harness.
- **`AGENTS.md`** — a tool-agnostic router that points AI coding agents at the usage docs and the top gotchas (complements the Claude-specific skill; distinct from the contributor-facing `CLAUDE.md`).

### Documentation

- Documented class-macro inheritance: `coercion_policy` / `unknown_attributes` / `immutable!` / `frozen!` inherit to subclasses and a child overrides them in isolation from the parent — with the asymmetry that `immutable!` / `frozen!` are one-way (a child can add but not un-set them). Covered in the README (a doctested example + table), `USAGE.md`, and the guide's common-mistakes list.

## [0.7.0] - 2026-05-28

Two adoption-focused additions: a JSON-to-FieldStruct scaffolder for modeling existing APIs and webhooks, and a `FieldStruct.root` path helper.

### Added

- **`FieldStruct::Scaffold.from_json`** — generates starter FieldStruct class source from a JSON example, or an array of same-shape examples. A *prototype you refine*: it reconstructs nesting (nested objects → nested classes emitted before their parent), maps arrays to `:array, of: …`, and types real JSON booleans/numbers, while keeping all strings as `:string` (a numeric-looking `authorization_code` must not become an Integer) and surfacing guesses as trailing comments. With multiple samples it resolves empty fields from other samples, drives `required`/`optional` from presence, and flags small repeated vocabularies as enum candidates. Non-identifier keys are snake-cased with a `serialize :json` mapping emitted. The developer adds enums, descriptions, and final scalar types — the comments point at where.
- **`FieldStruct.root`** — returns a `Pathname` to the library's root directory (the parent of `lib/`), computed from the entry file's location so it resolves to the repo root in development and to the installed gem directory when packaged.

## [0.6.0] - 2026-05-28

Type accuracy at the call site and ergonomics for editors and AI assistants: accurate stdlib signatures (backed by an RBS collection), an RBS generator for *your* FieldStruct subclasses, a dense `USAGE.md`, a bundled Claude Code skill, a schema view on `Metadata`, and README/USAGE examples that are now executed as doctests.

### Added

- **`FieldStruct::RBS.generate(klass)`** — emits RBS for the per-field accessors the `field` DSL defines on a subclass: a typed reader (nullability follows `required?`) and a permissive `(untyped) -> untyped` writer (the type coerces loose input). Handles nested structs, `:array` (`::Array[elem]`), `:union` (`(::A | ::B)`), `:boolean` (`bool`), `:value` (`untyped`), namespaced classes (module nesting), and inheritance (emits only own fields with `< ::Parent`). This is the deferred **D13 track 2** — Sord can't see these methods because they don't exist until you declare the fields. See the README "Type signatures" section for a Rake-task wiring example.
- **`Metadata#to_h`** — a copy-pasteable schema view keyed by field name (`type`, `ruby_type`, `required`, `default`, `options`, `description`), rendered as primitives/short names so you can `pp Klass.metadata.to_h` to see a model's shape without reading its source. The block form still delegates to `Enumerable#to_h` (so `Base#attributes` is unchanged).
- **`USAGE.md`** — a dense, example-first reference covering every type, field option, and class macro, plus validation/coercion semantics, JSON, nesting, registries, and gotchas. Ships in the gem package (`bundle show field_struct`) and is included in the YARD docs.
- **Claude Code skill** — `skills/field-struct/SKILL.md` gives an assistant the DSL, the common mistakes, and how to debug an invalid instance. The repo doubles as a single-plugin marketplace via `.claude-plugin/{plugin.json,marketplace.json}` (`/plugin marketplace add Paymentbox-com/field_struct`); the skill also ships in the gem for a no-marketplace copy into `.claude/skills/`.
- **RBS collection** — `rbs_collection.yaml` vendors the stdlib `date` / `time` / `bigdecimal` signatures so `sigs:validate` can resolve fully-qualified stdlib types. CI installs it and now runs the sig guards (`sigs:check` + `sigs:validate`), which the default `rake` task never exercised.
- **Doctested examples** — `spec/docs_examples_spec.rb` executes every ` ```ruby ` block in README.md / USAGE.md that is preceded by an invisible `<!-- doctest -->` marker, asserting `# =>` expectations by value comparison.

### Changed

- **The generated sig now reports accurate stdlib return types.** `coerce` on the Date/Time/DateTime/BigDecimal types is typed `-> ::Date?` / `::Time?` / `::DateTime?` / `::BigDecimal?` instead of resolving to the FieldStruct *wrapper* classes. Core type names in the YARD docs are fully-qualified (`::String`, `::Symbol`, `::Integer`) so Sord resolves them cleanly — this clears 38 "wasn't able to be resolved to a constant" warnings.
- **`rake sigs:validate`** loads the RBS collection (and installs it on first run) instead of running `--no-collection`.

### Notes

- The bundled plugin/marketplace manifests intentionally omit a pinned `version` (git-SHA tracked) to avoid drift from `version.rb`.

## [0.5.5] - 2026-05-27

Documentation tooling: a `rake docs:generate` task that builds the YARD HTML, plus a `release:check` umbrella that runs the full pre-flight battery before every release.

### Added

- **`rake docs:generate`** — builds YARD HTML to `doc/` with `--fail-on-warning`, so broken `{#method}` links and malformed tags fail the build instead of slipping into a release.
- **`rake docs:stats`** — `yard stats --list-undoc`; quick view of remaining coverage gaps.
- **`rake release:check`** — umbrella task that runs `spec`, `rubocop`, `sigs:check`, `sigs:validate`, and `docs:generate`. The pre-flight ritual before each release commit.
- **`.yardopts`** pinning the source list (`lib/**/*.rb`) and including `CHANGELOG.md` as an extra doc.
- `yard` added to the Gemfile as a direct dev dependency (it was already present transitively via `sord`).

### Fixed

- A few YARD `{#field}` / `{#immutable!}` links inside `class << self` were unresolvable because the targets are class methods, not instance methods. Switched to the `{.field}` / `{.immutable!}` (class-method) link syntax so the strict YARD build is warning-free.

## [0.5.4] - 2026-05-27

IRB-friendly inspect across every public object, plus an opt-in `FS` alias.

### Changed

- **Custom `#inspect` / `#pretty_print` across every surface object.** The default reflection-based output dumped every ivar, making FieldStruct objects in IRB look like a wall of text. Each library object now renders concisely:

  ```
  # Field
  #<FieldStruct::Field :level String enum=["beginner", "pro"]>
  #<FieldStruct::Field :address Nested(Address) required>
  #<FieldStruct::Field :payload Union(String | Integer)>

  # Metadata — one-line inspect lists field names; pp fans out:
  #<FieldStruct::Metadata fields=[:name, :age, :email]>
  #<FieldStruct::Metadata
    #<FieldStruct::Field :name String required>
    #<FieldStruct::Field :age Integer default=0>
    #<FieldStruct::Field :email String required format=/@/>>

  # Type instances
  #<FieldStruct::Types::String>
  #<FieldStruct::Types::Nested struct_class=Address>
  #<FieldStruct::Types::Union of=String | Integer>

  # Errors / Registry
  #<FieldStruct::Errors empty>
  #<FieldStruct::Errors name=["can't be blank"]>
  #<FieldStruct::Registry types=[:string, :integer, ...]>
  ```

- **`field` / `required` / `optional` now return the class `Metadata`** instead of the just-added `Field`. The Field is still available as `metadata[name]`. This makes IRB DSL output show the running set of declared fields rather than just the last one, and feeds the new Metadata pretty-print directly. No FieldStruct internals depended on the previous return value.

### Added

- **`FieldStruct.use_alias!`** — opt-in shortcut that defines a top-level constant (default `FS`) pointing back at `FieldStruct`, *and* swaps the prefix used by every `#inspect` method in the library so output reads with the short name too. Off by default. Raises `NameError` if the chosen constant is already taken by something else.

  ```ruby
  FieldStruct.use_alias!
  FS::Base              # => FieldStruct::Base
  User.metadata
  # => #<FS::Metadata
  #      #<FS::Field :name String required>
  #      #<FS::Field :age Integer>
  #    >
  ```

### Changed (continued)

- **`Metadata#pretty_print` closes `>` on its own line** so multi-field metadata reads as a tidy block rather than trailing the last field.

## [0.5.3] - 2026-05-27

Sord-generated RBS signatures.

### Added

- **RBS signatures (`sig/field_struct.rbs`).** Generated from YARD comments via Sord and shipped in the gem. Downstream tools (Solargraph, Steep, RBS-aware editors) get type info for the public surface without configuring anything. Three new rake tasks:
  - `rake sigs:generate` — regenerate from current YARD
  - `rake sigs:validate` — parse-check the committed sig file
  - `rake sigs:check` — fail if the committed sigs are stale (CI guard)
- **`sord` and `rbs` as Gemfile development dependencies.** Both `require: false`.

The custom Metadata→RBS generator for *user-defined* FieldStruct subclasses (per D13 in the plan) remains deferred — Sord covers the library's hand-written classes; the user-class generator is its own future effort.

## [0.5.2] - 2026-05-27

Field-level documentation metadata.

### Added

- **Field-level `description:` (aliased as `desc:`).** Attach a human-readable description to any field for downstream documentation generators.

  ```ruby
  required :email, :string, description: 'Primary contact email'
  required :age,   :integer, desc: 'Age in years'
  ```

  Stored as a first-class attribute on `Field` (`field.description`, with `field.desc` as a reader alias) — not in `Field#options`. Documentation metadata only: does not appear in `attributes` / `as_json` / pattern matches. Passing both `description:` and `desc:` raises `ArgumentError`. Subclass re-declarations replace the inherited description (including back to `nil` if not provided).

## [0.5.1] - 2026-05-27

Two internal refactors that set the gem up for an eventual RBS generator
and improve IDE / Sord / Solargraph readings of the public surface. No
behavior change.

### Changed

- **`Type#coerce` signatures are now typed kwargs.** Each type's `coerce` method declares the options it consumes as named keyword arguments with a trailing `**` catch-all. The Hash-as-positional pattern is gone from the type contract; the loose base contract is `def coerce(value, **) = raise NotImplementedError` and each subclass narrows. Sets the gem up for an eventual RBS generator that emits useful per-type signatures.

  ```ruby
  # Before
  def coerce(value, options = {})
    fmt = options[:format] || self.class.default_format
  end

  # After
  def coerce(value, format: self.class.default_format, **)
    # fmt is bound directly
  end
  ```

  The setter pipeline splats `field.options` at the call site (`coerce(value, **field.options)`), so the Hash storage on `Field` is unchanged. Existing call sites that pass options as kwargs are unaffected; the rare positional Hash needs explicit braces (`type.coerce({key: 'val'})`) to be the value, not options.

- **Internal DSL helpers are now functional**, returning new Hashes instead of mutating in place. `apply_default_format!`, `resolve_array_options!`, `build_union_instance!` → `apply_default_format`, `resolve_array_options`, `build_union_instance`. Callers update via reassignment in `Base.field`.

- **YARD `@param` types tightened library-wide.** Type coerce methods, value-object attrs (Field/Metadata), DSL macros (`field`, `coercion_policy`, `unknown_attributes`, `validate`), and the Errors family all now declare the actual accepted union types instead of generic `[Object]` / `[Hash]`. Duck-typed inputs use `#to_x` interface notation (`[Date, #to_date, String, nil]`). Strictly-bounded types name the exact set (`Symbol#coerce` is `[Symbol, String, nil]`). Documentation-only — zero behavior change.

## [0.5.0] - 2026-05-27

Per-type field options + presets.

### Added

- **`round:` option on `:big_decimal` / `:decimal` / `:float`** — Integer that controls `.round(n)` after coercion.
- **`values:` option on `:boolean`** — Hash `{truthy: [...], falsy: [...]}` for explicit vocabularies, or a Symbol preset. Built-in presets: `:english_yes_no`, `:english`, `:numeric`.
- **`format:` option on `:date` / `:datetime` / `:time`** — strftime/strptime String (or Symbol preset), applied in both directions: input strings parse via `strptime`, output via `strftime`. Built-in presets: `:iso8601`, `:rfc2822`, `:db`, plus `:us` / `:eu` for `:date`.
- **`format:` Symbol-preset support on `:email` / `:uuid` / `:url`** — the existing Regexp option now also accepts named presets. `:email` → `:permissive`/`:default`/`:strict`; `:uuid` → `:any_version`/`:v4`/`:v7`; `:url` → `:http`/`:https_only`/`:any_scheme`.
- **`Types::Base.resolve_options(options)` hook** — a per-type seam for resolving Symbol presets at field-declaration time. Pass-through by default; subclasses override to interpret their own options.
- **`Types::PresetResolver`** and **`Types::TimeFormatResolver`** — small helpers used by the built-in types; downstream type subclasses can reuse them.

### Changed

- **`DEFAULT_FORMAT` / `TRUTHY_STRINGS` / `FALSEY_STRINGS` constants removed.** The defaults live on class methods (`default_format`, `default_truthy`, `default_falsy`) so subclasses can override with a one-line method instead of redeclaring a constant. Existing callers that reach for `Types::UUID::DEFAULT_FORMAT` etc. must call `Types::UUID.default_format` instead.
- **`format:` validator loosened** — previously restricted to string-shaped types. Time-shaped types (`:date`, `:time`, `:datetime`) are now also format-aware (with strftime/strptime semantics). Non-format-aware types still raise.

## [0.4.0] - 2026-05-27

Serialization-formats redesign. Aliases are no longer a per-field
attribute; they're a class-level mapping declared via the new
`serialize` macro and consulted only by JSON I/O.

### Added

- **`serialize` class macro.** Declares an import/export mapping for a named
  format, stored on `Metadata#serializations`:

  ```ruby
  class User < FieldStruct::Base
    required :first_name, :string
    serialize :json, first_name: 'firstName'
  end
  ```

  Internal-symbol on the left, external-string on the right; the same
  mapping applies to both directions. Fields not listed use their
  canonical name. Multi-format coexistence is allowed (`:json`, `:csv`,
  …); only `:json` is wired in-gem (downstream gems can read
  `Klass.metadata.serializations[:their_name]` for their own I/O).
  Mapping keys must be declared fields — undeclared keys raise
  `ArgumentError` at class load.

### Changed

- **`as_json` / `to_json`** apply the `:json` mapping when one is declared
  (identity otherwise). Round-trip via `Klass.from_json(instance.to_json)`
  preserves structural equality.
- **`from_json`** reverse-maps the parsed hash recursively (through nested
  FieldStructs and arrays of nested) before calling `.new`.

### Removed (breaking)

- **`aliases:` field option** — per-field alias declarations are gone.
  Lift them up to a `serialize :json, ...` block on the class.

  ```ruby
  # Before:
  required :first_name, :string, aliases: ['firstName']

  # After:
  required :first_name, :string
  serialize :json, first_name: 'firstName'
  ```

- **`aliased: true` kwarg** on `attributes` / `to_h` / `as_json` /
  `to_json` — no longer accepted. `to_json` already applies the
  declared mapping; `to_h` / `attributes` stay canonical.
- **`Field#aliases`**, **`Field#export_name`**, and **`Metadata#field_for`**
  removed from the public surface. `Metadata#[name]` is the canonical
  lookup; lookup by external name is the serializer's concern.

## [0.3.2] - 2026-05-27

Ruby pattern matching support.

### Added

- **Pattern matching** — every FieldStruct instance now works as a Ruby 3.0+ pattern target. `deconstruct_keys(keys)` returns the canonical-name attribute hash (sliced down when keys is given, full when keys is `nil`); `deconstruct` returns field values in declaration order. Nested FieldStructs recurse naturally because every subclass inherits the same protocol. Aliases and `errors` do not participate (patterns match data, not validity, and use canonical names — the Ruby-side convention). Frozen and immutable instances work identically.

## [0.3.1] - 2026-05-27

Two small ergonomics improvements on top of v0.3.0.

### Added

- **Callable defaults** — `default:` now accepts a literal OR a parameterless callable (Proc, Lambda, Method, anything that responds to `#call`). Callables are invoked once per instance during apply_defaults; the return value flows through the setter pipeline like any other default. Safe for per-instance values like timestamps or generated IDs.
- **`FieldStruct.new_registry`** — shorthand for building a namespace registry. Defaults the parent to `FieldStruct.types`; an explicit `nil` parent gives an unparented registry. The block (optional) is evaluated in the new registry's instance scope, so `register :money, Acme::Money` works without a receiver.

## [0.3.0] - 2026-05-27

Phase 2 wave two: union types, the `:binary` extended type, and the
`frozen!` class macro. All five Phase 2+ backlog items that belong
in-gem are now landed; RBS gen / format converters / docs generator
remain deferred to separate downstream gems.

### Added

- **`:binary` extended type** — Types::Binary subclasses Types::String and forces ASCII-8BIT encoding on the coerced value. `missing?` is nil-or-empty only (whitespace bytes are meaningful). Designed for raw bytes / BLOBs.
- **`frozen!` class macro** — instances are Ruby-frozen at the end of `initialize`; subsequent ivar mutations raise `FrozenError`. Inherited by descendants. Independent of `immutable!` (which uses our custom `ImmutableError`). The two can stack.
- **Union types** — `optional :payload, :union, of: [Payload, :boolean]`. Each member type is tried in declared order; the first that doesn't raise wins. Member-coercion errors are caught broadly (ArgumentError, TypeError, FieldStruct::Error); unrelated bugs still propagate. If every member rejects, the union raises `TypeError` and the parent's `coercion_policy` engages. `ruby_type` returns a flat, deduplicated `Array<Class>` across all members. Declaration-time guards require `of:` to be an Array with at least two members.

## [0.2.0] - 2026-05-27

Phase 2 first wave. Nested struct support, JSON import, field-name
aliases, cross-field validation, field-level coercion policy override,
extended scalar types (`:symbol`, `:uuid`, `:url`, `:email`), and
`enum:` / `in:` value-restriction field options.

### Added

- **Nested FieldStructs** — declare `field :address, Address` where `Address < FieldStruct::Base`. Coerce nil / instance / Hash; eager `'is invalid'` stamp on the parent at assignment time; inner construction errors (`UnknownAttributeError`, `CoercionError`) propagate to the caller rather than being caught by the parent's `coercion_policy`. Arrays of nested work via `of:` (class or symbol form). `as_json` deep-walks. `Types::Nested` is the wrapping type; `Field` accepts a pre-built `type_instance:` so parameterized types flow through the same plumbing as stock types.
- **`Klass.from_json(string)`** — JSON import driven off Metadata. Parses with Oj, feeds through `initialize`, so coercion / nested construction / `unknown_attributes` / `coercion_policy` engage as normal. Non-object JSON roots raise `ArgumentError`; malformed JSON propagates the underlying parse error. Round-trips structurally for every base type except `:value`.
- **Extended scalar types** — `:symbol`, `:uuid`, `:url`, `:email`. The string-shaped trio (`:uuid` / `:url` / `:email`) subclasses `Types::String` and pre-fills the field's `format:` option from a class-level `default_format`. Users can override with `format: /.../`.
- **`enum:` and `in:` field options** — two parallel "value must be one of these" options. `enum: [...]` works on string-like types (`:string`, `:symbol`, and subclasses including `:uuid` / `:url` / `:email`). `in: [...]` or `in: range` works on rangy types (`:integer`, `:float`, `:decimal`, `:date`, `:time`, `:datetime`); accepts an Array or any Range. Both run post-coercion. Mismatch is a `'is invalid'` validation error, mirroring `format:`. Declaration-time guards reject the wrong combination.
- **Field-level `coercion_policy:` override** — `field :x, :integer, coercion_policy: :raise` overrides the class default for a single field. Falls back to the class macro when not specified. Unknown values raise `ArgumentError` at class load.
- **Cross-field validation** — `validate { |record| ... }` blocks and `validate :method_name` symbol form (interchangeable, can be mixed and stacked). Validators run at the end of `initialize` and on every `valid?` call. Convention is `errors.add(:base, '...')`; `errors[:base]` is cleared between cross-field runs, while field-level setter errors are preserved. Validators are inherited by subclasses (the subclass receives a `dup` of the parent's list and appends its own). Classes with no `validate` declarations keep Phase 1's cheap `valid? = errors.empty?` behavior.
- **Field-name aliases** — declare `field :email, :string, aliases: ['EmailAddress', 'email_address']` to bridge external naming conventions. Import accepts any declared alias (canonical wins on conflict); export opts in via `as_json(aliased: true)` / `to_json(aliased: true)` / `to_h(aliased: true)` / `attributes(aliased: true)` using each field's first alias. `unknown_attributes :raise` treats aliases as known. Aliases propagate through nested FieldStructs. No Ruby-side getter/setter methods are auto-defined for alias names — Ruby code always uses the canonical name. `Field#aliases` is a first-class attribute and `Metadata#field_for(name)` looks up by canonical-or-alias.

## [0.1.0] - 2026-05-27

Initial release. Typed-PORO foundation: declared fields with enforced
types, presence checks, per-field validation, and an ActiveModel-shaped
public surface that reuses no ActiveModel code.

### Added

- **DSL macros** — `field`, `required`, `optional` for declaring
  attributes. Type is the second positional argument.
- **Class macros** — all inherited by descendants, all overridable:
  - `coercion_policy :keep_raw | :replace | :raise` (default `:keep_raw`)
  - `immutable!` — one-way switch; setters post-`initialize` raise
    `FieldStruct::ImmutableError`
  - `unknown_attributes :ignore | :raise` (default `:ignore`)
- **Base types** — `:string`, `:immutable_string`, `:integer`, `:float`,
  `:big_decimal` (with `:decimal` alias), `:boolean`, `:date`, `:time`,
  `:datetime`, `:value`, `:array` (with required `of:` element type).
- **Per-field validation on assignment** — every setter runs
  `coerce → store → presence-check → format-check`, and the setter owns
  its field's errors.
- **`format:` field option** for string-shaped fields; declaration-time
  guard against use on non-string types.
- **Registry** — `FieldStruct::Registry` with parent-chain lookup;
  `FieldStruct.types` is the seeded base. Namespaces extend by defining
  a module-level `field_types` method.
- **Inheritance** — subclasses inherit parent metadata, parent
  declarations are not mutated when a child adds or shadows a field.
- **AM-shaped public surface** (interface only, no AM code reuse):
  `valid?`, `invalid?`, `errors`, `attributes`, `attribute_names`,
  `assign_attributes`, `to_h`, `as_json`, `to_json` (via Oj), `inspect`,
  `model_name`, `to_model`.
- **Structural equality** — `==` / `eql?` / `hash` over
  `[class, attributes]`; errors ignored.
- **`FieldStruct::Errors`** value object — `[]`, `add`, `clear`,
  `empty?`, `to_h`, `messages`.
- **Error classes** — `FieldStruct::Error` (base),
  `FieldStruct::CoercionError`, `FieldStruct::ImmutableError`,
  `FieldStruct::UnknownAttributeError`.
- **YARD comments** on the public surface.

### Notes

- Boolean's `ruby_type` returns `[TrueClass, FalseClass]` because Ruby
  has no Boolean class — the contract is "Class or Array<Class>"
  (`Value#ruby_type` is `Object`).
- Array coercion is whole-value under `coercion_policy`: a single bad
  element causes the array to be treated as one uncoercible value, and
  the class's policy applies to that whole array. Per-element policy
  is a Phase 2 candidate.
