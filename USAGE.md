# FieldStruct — usage reference

Dense, example-first reference for using the `field_struct` gem. Optimized for an
agent (or human) to load once and use the whole API correctly. For narrative
docs see `README.md`; for design rationale see `docs/origin/plan.md`.

**Mental model:** declare fields on a `FieldStruct::Base` subclass. Each field
gets a coerced, typed reader/writer and presence/format validation. Construction
and validity are *separate* — you can build an invalid instance; ask `valid?`.

<!-- doctest -->
```ruby
class User < FieldStruct::Base
  required :name, :string
  optional :age,  :integer
end

u = User.new(name: 'Alice', age: '30') # string + symbol keys both work
u.name        # => "Alice"
u.age         # => 30
u.attributes  # => { name: "Alice", age: 30 }
u.valid?      # => true
```

---

## Types

Register name in the first column; use it as the second arg to `field`/`required`/
`optional`. "Coerces from" is what the setter accepts (`nil` always passes through
as `nil`). "Missing" is what counts as absent for presence checks.

| Name | Ruby type | Coerces from | Type options | Missing when |
|------|-----------|--------------|--------------|--------------|
| `:string` | `String` | `value.to_s` (`strict: true`: scalars and `to_str` only) | `format:`, `enum:`, `strict:` | nil / empty / whitespace-only |
| `:immutable_string` | `String` (frozen) | `to_s`, then frozen dup | `format:`, `enum:`, `strict:` | nil / empty / whitespace |
| `:integer` | `Integer` | strings in base 10 (`"010"` → 10; `"0x1A"`/`"3.14"` raise), or `base:`; floats truncate (`strict: true`: refused unless whole) | `in:`, `base:`, `strict:` | nil |
| `:float` | `Float` | `Kernel.Float` (strict; base-10 strings only — `"0x1A"` raises; NaN/±Infinity refused) | `round:`, `in:` | nil |
| `:big_decimal` (alias `:decimal`) | `BigDecimal` | BigDecimal/Integer/Float/numeric string (NaN/±Infinity refused) | `round:`, `in:` | nil |
| `:boolean` | `true`/`false` | `true`/`false`, `1`/`0`, and only the strings `"true"`/`"1"`/`"false"`/`"0"` (case-insensitive; `"yes"` needs `values:`, see below) | `values:` | nil |
| `:date` | `Date` | `Date`, `DateTime`/`Time` (narrowed), String | `format:`, `in:` | nil |
| `:time` | `Time` | `Time`, `Date`/`DateTime` (from components), String | `format:`, `in:` | nil |
| `:datetime` | `DateTime` | `DateTime`, `Date`/`Time` (from components), String | `format:`, `in:` | nil |
| `:symbol` | `Symbol` | `Symbol`, `String#to_sym` (else `TypeError`) | `enum:` | nil |
| `:uuid` | `String` | `to_s` | `format:` (`:any_version`/`:v4`/`:v7`), `enum:`, `strict:` | nil / empty / whitespace |
| `:url` | `String` | `to_s` | `format:` (`:http`/`:https_only`/`:any_scheme`), `enum:`, `strict:` | nil / empty / whitespace |
| `:email` | `String` | `to_s` | `format:` (`:permissive`/`:default`/`:strict`), `enum:`, `strict:` | nil / empty / whitespace |
| `:binary` | `String` (ASCII-8BIT) | `to_s`, forced to binary encoding | `format:` (Regexp), `enum:`, `strict:` | nil / empty (**whitespace bytes are kept**) |
| `:value` | `Object` (untyped) | pass-through, no coercion | — | nil |
| `:array` | `Array` | each element coerced through `of:` (with `element:` options) | `of:` (**required**), `element:` | nil / empty |
| `:union` | first matching member | tries each member type | `of:` (**Array, ≥2**) | nil |
| nested (a `FieldStruct::Base` subclass) | that class | Hash → instance, or instance | — | nil |

```ruby
required :id,        :uuid, format: :v4
required :website,   :url,  format: :https_only
optional :email,     :email                       # default regex
required :status,    :symbol, enum: %i[active archived]
required :score,     :integer, in: 0..100
required :price,     :big_decimal, round: 2
required :code,      :integer, base: 16           # "1A" → 26
optional :tags,      :array, of: :string
optional :ids,       :array, of: :integer, element: { strict: true }
required :ref,       :union, of: %i[string integer]
optional :address,   Address                       # nested FieldStruct
optional :lines,     :array, of: LineItem          # array of nested
```

**Each type describes its own options at runtime** — you don't have to trust this
table. `FieldStruct.types.lookup(:date).option_schema` returns
`{ format: {type:, required:, presets:}, in: {...} }`. The DSL validates these
*native* options at class load: a wrong-shaped value (`round: '2'`) or a
misapplied option (`enum:` on `:integer`) raises with the expected shape / the
types it applies to. An option the type doesn't recognize is **not** an error —
it's stored verbatim on the `Field`, so downstream tooling (e.g. an Avro exporter)
can stash and read its own options.

---

## Field options (any type)

| Option | Meaning |
|--------|---------|
| `required: true` | presence-checked (`required :x` is sugar; `optional :x` / bare `field :x` are not) |
| `default:` | literal, **or** a callable (`-> { Time.now }`, a Proc/Method) invoked once per instance |
| `coercion_policy:` | `:keep_raw` (default) \| `:replace` \| `:raise` — per-field override of the class setting |
| `description:` / `desc:` | human text; introspection only — **never** in `attributes`/`as_json`/pattern match |
| `rbs_type:` | String of RBS that `FieldStruct::RBS` emits for this field instead of the derived type (`'::ActiveRecord::Relation'`); signatures only, no runtime effect |
| `sensitive:` | `true` renders `[FILTERED]` for the value in `inspect` / `pp`; data paths unchanged — see [Log safety](#log-safety-error-messages-and-sensitive-fields) |

```ruby
class Account < FieldStruct::Base
  required :id,         :uuid, default: -> { SecureRandom.uuid }, desc: 'primary key'
  optional :balance,    :big_decimal, default: 0, coercion_policy: :raise
end
```

Type-specific options: `format:` (string-shaped + date/time/datetime — a regex or a
strftime string or a preset Symbol), `round:` (float/decimal — Integer places),
`base:` (integer — radix 2..36 for string input, default 10), `strict:` (string-shaped
and integer — Boolean; see [Strict coercion](#strict-coercion-strict-true)),
`values:` (boolean — a `{truthy:, falsy:}` Hash or a preset Symbol), `of:` (array
element type / union member array), `element:` (array — a Hash of the element
type's own options; see [Element options](#element-options-element)), `enum:` (string-like — Array of allowed values),
`in:` (numeric/temporal — Array or Range), `zone:` (time/datetime — `"UTC"`,
`"±HH:MM"` or an IANA name like `"America/Denver"` for zone-less input; see [Zones](#zones-zone)).

```ruby
required :joined, :date, format: '%m/%d/%Y'   # custom strftime
required :paid,   :boolean, values: :english_yes_no
required :flag,   :boolean, values: { truthy: %w[on], falsy: %w[off] }
```

Boolean presets: `:english_yes_no`/`:english` (`true yes y on 1` / `false no n off 0`),
`:numeric` (`1`/`0`). Date presets: `:iso8601 :us :eu`. Time/DateTime presets:
`:iso8601 :rfc2822 :db`.

### The numeric contract

- **Integer strings are base 10.** `"010"` is 10 and `"007"` is 7 — not octal —
  and `"0x1A"` / `"0b11"` are refused rather than read as hex/binary. Surrounding
  whitespace and digit underscores are fine (`" 42 "` → 42, `"1_000"` → 1000).
  Declare `base:` (2..36, checked at class load) for another radix:
  `field :code, :integer, base: 16` reads `"1A"` as 26. Integers pass through and
  Floats still truncate; `base:` only affects strings.
- **Float strings are base 10 too.** `"0x1A"` (which `Kernel.Float` reads as 26.0)
  is refused, like `"0b101"` and `"0o17"`. Every other `Kernel.Float` form still
  reads: `"1_000.5"`, `" 2.5 "`, `"1e3"`, `".5"`, `"017"` (→ 17.0).
- **NaN and ±Infinity are never valid.** `:integer`, `:float` and `:decimal` refuse
  them — as a Float, a BigDecimal, a String (`"NaN"`, `"Infinity"`) or JSON `1e400` —
  as an ordinary coercion failure under the field's `coercion_policy`. A `:union`
  refuses a non-finite Float/BigDecimal outright rather than letting a `:string`
  member store `"NaN"`. Like every FieldStruct message, these name the input class,
  never the value — see [Log safety](#log-safety-error-messages-and-sensitive-fields).
- **`round:` keeps the field's type and rounds half up** (ties away from zero).
  `round: 0` returns a `Float` / `BigDecimal`, not an Integer, and `:decimal`
  ignores the process-global `BigDecimal.mode` — a host that sets banker's rounding
  still gets `12.345` → `12.35` at `round: 2`.

### Strict coercion (`strict: true`)

The defaults are lenient on purpose — they match what ActiveModel does, so a Rails
client sees the same values. A field that must not accept "close enough" (amounts,
account numbers) can opt in per field with `strict: true`. Strict only *narrows*:
anything it accepts becomes exactly what the default would make of it.

| Input | `:string` | `:string, strict: true` | `:integer` | `:integer, strict: true` |
|-------|-----------|-------------------------|------------|--------------------------|
| `"abc"` / `"42"` | `"abc"` / `"42"` | same | — / 42 | — / 42 |
| `:abc` | `"abc"` | `"abc"` | `TypeError` | `TypeError` |
| `42` | `"42"` | `"42"` | 42 | 42 |
| `12.0` / `BigDecimal("12.0")` | `"12.0"` / `"0.12e2"` | `TypeError` | 12 / 12 | 12 / 12 |
| `12.7` / `Rational(25, 2)` | `"12.7"` / `"25/2"` | `TypeError` | 12 (truncated) | `ArgumentError` |
| `"12.7"` / `"12.0"` / `"1e3"` / `"0x1A"` | as-is | as-is | `ArgumentError` | `ArgumentError` |
| object with `to_str` | `to_s` | `to_s` | read as its `to_str` string | read as its `to_str` string |
| `{a: 1}` / `[1]` / `true` / `Time` / `Object.new` | their `to_s` | `TypeError` | `TypeError` (a `Time` reads as its epoch) | `TypeError` (a `Time` → `ArgumentError`) |
| `Float::NAN` / `Infinity` | `"NaN"` / `"Infinity"` | `TypeError` | `ArgumentError` | `ArgumentError` |

- **`:string` strict** accepts a String, a Symbol, an Integer and anything
  responding to `to_str`. An Integer counts because a JSON payload often carries an
  identifier as a number (`"account": 12345`) and its text is unambiguous. A Float,
  BigDecimal or Rational is refused: its `to_s` (`"1.0e+20"`, `"0.12e2"`, `"1/2"`)
  is not the text the sender meant. Booleans, Hashes,
  Arrays, Complex and other objects are refused — their `to_s` is a rendering, not
  a value. It applies to the string subtypes too (`:immutable_string`, `:uuid`,
  `:url`, `:email`, `:binary`).
- **`:integer` strict** accepts a value only when it *is* a whole number: an
  Integer, or a numeric equal to its integer (`12.0`, `BigDecimal("12")`,
  `Rational(24, 2)`). Strings follow the default rules exactly — integer digits in
  base 10 or `base:` — so a float-shaped string like `"12.0"` or `"1e3"` is refused
  in both modes.
- Refusals are ordinary coercion failures under the field's `coercion_policy`, and
  their messages name the input class, never the value.
- `strict:` must be `true`/`false` (checked at declaration); on any other type it
  raises `strict: option does not apply to Float fields. It applies to: String, ImmutableString, Integer, …`

<!-- doctest -->
```ruby
class Charge < FieldStruct::Base
  required :reference, :string,  strict: true
  required :cents,     :integer, strict: true
end

Charge.new(reference: :ord_1, cents: 1250.0).cents   # => 1250
Charge.new(reference: { id: 1 }, cents: 1).valid?     # => false
Charge.new(reference: 'ord_1', cents: 12.5).valid?    # => false
```

**`:boolean` strings.** By default a `:boolean` field takes `true`, `false`, `1`,
`0` and exactly four strings, matched case-insensitively and not stripped:
`"true"`, `"1"`, `"false"`, `"0"`. `"yes"`, `"on"` and `"t"` are coercion failures.
To accept them, name a preset — `values: :english_yes_no` (alias `:english`) takes
`true/yes/y/on/1` and `false/no/n/off/0`; `:numeric` takes only `"1"`/`"0"` — or
pass a Hash `{truthy: [...], falsy: [...]}`. A Hash **replaces** the default strings
rather than adding to them: with `values: {truthy: %w[si], falsy: %w[no]}`,
`"true"` is refused. The literals `true`/`false`/`1`/`0` are always accepted.

<!-- doctest -->
```ruby
class Prefs < FieldStruct::Base
  optional :plain, :boolean
  optional :yn,    :boolean, values: :english_yes_no
  optional :es,    :boolean, values: { truthy: %w[si], falsy: %w[no] }
end

Prefs.new(plain: 'TRUE').plain   # => true
Prefs.new(plain: 'yes').valid?   # => false
Prefs.new(yn: 'yes').yn          # => true
Prefs.new(es: 'SI').es           # => true
Prefs.new(es: 'true').valid?     # => false
Prefs.new(es: true).es           # => true
```

### The temporal contract

Three rules apply to `:date` / `:time` / `:datetime`, and they exist because the
stdlib parsers answer questions they were not asked.

- **A declared `format:` anchors.** `'2026-07-031'` under `'%Y-%m-%d'` is refused
  rather than read as the 3rd with the trailing character dropped. "Anchor" means
  trailing-junk rejection and nothing more — a hand-written format stays
  strptime-lenient about widths and sign, because `%m` accepting one or two digits
  is strptime's contract.
- **A day that never existed is refused**, by all three types. `'2026-06-31'` is
  not 1 July.
- **With no declared format, the string must name a whole day.** `Time.parse('10:30')`
  is *today* at 10:30 and `'July'` is 1 July of this year; a value whose meaning
  depends on when it was parsed is not a value. A *declared* partial format
  (`format: '%H:%M'`) is a deliberate choice and still works.

A blank string is a coercion failure, as it already was for `:integer`, `:float`,
`:big_decimal` and `:boolean`. Only `:string` treats blank as missing.

**`format: :iso8601` is RFC 3339**, which is what "ISO-8601" means in an API
contract and what JSON Schema's `date-time` refers to. FieldStruct parses and
renders it itself rather than delegating to `Time.iso8601` / `DateTime.iso8601`,
which disagree with each other (and `Time.iso8601` reads `2026-02-30T10:30:00Z`
as 2 March). It accepts full-width fields, a `T` separator (or lowercase `t`), whole seconds,
optional fractional seconds, and a **mandatory** offset: `Z` (or `z`), `±hh:mm`,
or `±hhmm` without the colon (FieldStruct 0.9.0 wrote that form, so it still
reads it back); it refuses `2026-7-3`, `+2026-07-03`, `20261-07-03`, `20260703`, week and ordinal
dates, a missing offset, hour 24 and second 60. Output is `Z` for UTC and
`+HH:MM` otherwise.

```ruby
required :on, :date,     format: :iso8601   # 2026-07-03 exactly, and a real day
required :at, :datetime, format: :iso8601   # 2026-07-03T10:30:00Z, offset required
```

**A `Z` under `format: :iso8601` is a fixed `+00:00` offset, not UTC.** On a
`:time` field the result has `utc_offset == 0` but `utc? == false` (it is the same
instant, and `==` still holds). `zone: 'UTC'` does not change that: it only fills
in a *missing* offset, and an RFC 3339 string always has one. If you need `utc?`,
call `.utc` on the value, or leave `format:` off — the default parser reads `Z` as
UTC — and add `zone: 'UTC'` if zone-less strings should land in UTC too.

<!-- doctest -->
```ruby
class Stamp < FieldStruct::Base
  optional :rfc,   :time, format: :iso8601
  optional :rfc_u, :time, format: :iso8601, zone: 'UTC'
  optional :plain, :time, zone: 'UTC'
end

s = Stamp.new(rfc: '2026-07-03T10:30:00Z', rfc_u: '2026-07-03T10:30:00Z',
              plain: '2026-07-03T10:30:00Z')
s.rfc.utc_offset            # => 0
s.rfc.utc?                  # => false
s.rfc_u.utc?                # => false
s.plain.utc?                # => true
s.rfc == s.plain            # => true
Stamp.new(plain: '2026-07-03 10:30').plain.utc?   # => true
```

That strictness is the point: it is what lets you declare the field instead of
hand-rolling `format: /\A\d{4}-\d{2}-\d{2}\z/` plus a validator. The other
presets (`:us`, `:eu`, `:db`, `:rfc2822`) are display and interchange formats, so
they stay strftime-based — with anchoring and civil-date validity still applied.

### Zones (`zone:`)

By default a zone-less string follows the stdlib semantics of the type you
declared: `:time` uses `Time.parse` and lands in the *process* zone, `:datetime`
uses `DateTime.parse` and lands in **UTC**. So `"2026-10-22 10:00"` in a `:time`
field is a different instant on a server in Denver than on one in Tokyo.

Declare `zone:` on a `:time` or `:datetime` field to name the zone a zone-less
value means. The same input then gives the same answer on any server. `zone:`
only fills in a **missing** offset — it never changes one the input carries.

`zone:` takes `"UTC"`, a fixed offset (`"-06:00"`, the same all year) or an IANA
name (`"America/Denver"`, which follows daylight saving: -06:00 in July, -07:00 in
January). With a name, a wall-clock time gets the offset in force **at that date**.

| Input | no `zone:` | `zone: "-06:00"` | `zone: "America/Denver"` |
|-------|------------|------------------|--------------------------|
| `"2026-10-22 10:00"` (no offset) | `:time` process zone; `:datetime` UTC | 10:00 at -06:00 | 10:00 at Denver's offset that day (`"2026-01-15 10:00"` → -07:00) |
| a `format:` without `%z` (`:db`, `'%H:%M'`) | as above | 10:00 at -06:00; a date the format omits is *today in -06:00* | the same, at that date's offset; an omitted date is *today in Denver* |
| `"2026-10-22T10:00:00+02:00"`, `"… Z"`, `"… EST"` | its own offset | its own offset (unchanged) | its own offset (unchanged) |
| `"2026-10-22 10:00 XYZ"`, `"… America/Denver"` (a zone in the *string*) | `:time` process zone; `:datetime` UTC | refused — `zone:` won't override a stated zone | refused, likewise |
| `Time` / `DateTime` / TimeWithZone | instant and offset kept | instant and offset kept (not converted) | instant and offset kept (not converted) |
| `Date` | midnight: `:time` process zone, `:datetime` UTC | midnight at -06:00 | midnight at that day's offset |
| an epoch string under `format: '%s'` | that instant, in the process zone (`:time`) or UTC (`:datetime`) | that instant, at -06:00 | that instant, at Denver's offset at that instant |
| Integer (epoch seconds) | refused | refused | refused |

- **Accepted values:** `"UTC"` (the `:time` value is then `utc?`), fixed offsets
  `"+HH:MM"` / `"-HH:MM"` from `-23:59` to `+23:59` (colon required), and IANA
  `Area/Location` names in the zone database (`"America/Denver"`, `"Etc/UTC"`,
  `"America/Argentina/Buenos_Aires"`). Anything else raises `ArgumentError` at
  declaration, naming the option: `"utc"`, `"Z"`, `"-0600"`, an unknown name, and
  abbreviations or legacy aliases with no `/` — `"MST"` is in the zone database,
  but as a fixed -07:00, not Mountain time with DST, so it is refused rather than
  quietly meaning something else.
- **Rails zone names are refused** (`"Mountain Time (US & Canada)"`). They are
  ActiveSupport aliases that exist only when ActiveSupport is loaded, so accepting
  them would make the same declaration valid in one process and invalid in another.
  Use the IANA name they map to (`ActiveSupport::TimeZone::MAPPING[name]`).
- **Daylight-saving edges** (names only — a fixed offset has none):
  - A wall-clock time the zone **skips** (`"2026-03-08 02:30"` in Denver, inside the
    spring-forward hour) is refused: `could not be coerced: names a local time that
    does not exist in America/Denver (skipped by a daylight-saving change)`. It names
    no instant, like the 30th of February. ActiveSupport moves it an hour forward
    (03:30); FieldStruct does not guess.
  - A wall-clock time the zone **repeats** (`"2026-11-01 01:30"`, which happens at
    -06:00 and again at -07:00) is read at the **daylight-time** offset, the earlier
    instant — what ActiveSupport's `TimeWithZone` picks, so a Rails app sees the
    same answer.
  - A `Date` whose midnight the zone skips becomes the **first moment** of that day
    (01:00 -03:00 in `America/Santiago` on 6 September 2026), as `Date#in_time_zone` does.
- **What you get back** is a plain `Time` (or `DateTime`) with that offset — never a
  `TZInfo::TimeWithOffset`, and it does not remember the zone: `Time#zone` is `nil`
  and adding a day keeps the offset rather than following DST. Re-assign to re-read.
- **Dependency:** the zone database is [tzinfo](https://github.com/tzinfo/tzinfo)'s
  (a runtime dependency since 0.14), required only when a field declares a name — a
  `"UTC"` or fixed-offset field never loads it. tzinfo reads the OS zoneinfo
  (`/usr/share/zoneinfo`); on a system without it (Windows, slim containers) a
  declaration raises `ArgumentError` saying to add the `tzinfo-data` gem.
- `zone:` has no effect with `format: :iso8601`, which requires an offset anyway.
  It does not apply to `:date` (a date has no time of day to place).

<!-- doctest -->
```ruby
class Shift < FieldStruct::Base
  required :starts, :time,     zone: '-06:00'
  optional :logged, :datetime, zone: 'UTC'
  optional :ends,   :time,     zone: 'UTC', format: :db
  optional :local,  :time,     zone: 'America/Denver'
end

shift = Shift.new(starts: '2026-10-22 10:00', ends: '2026-10-22 18:30:00')
shift.starts.utc_offset                                    # => -21600
shift.starts.hour                                          # => 10
shift.ends.utc?                                            # => true
Shift.new(starts: '2026-10-22T10:00:00+02:00').starts.utc_offset   # => 7200
Shift.new(starts: '2026-10-22 10:00', logged: '2026-10-22 10:00').logged.offset   # => 0

Shift.new(starts: '2026-07-01 10:00', local: '2026-07-01 10:00').local.utc_offset  # => -21600
Shift.new(starts: '2026-01-15 10:00', local: '2026-01-15 10:00').local.utc_offset  # => -25200
Shift.new(starts: '2026-11-01 10:00', local: '2026-11-01 01:30').local.utc_offset  # => -21600
gap = Shift.new(starts: '2026-03-08 10:00', local: '2026-03-08 02:30')
gap.errors[:local].first.end_with?('does not exist in America/Denver (skipped by a daylight-saving change)')  # => true
```

---

## Class macros

```ruby
class Doc < FieldStruct::Base
  immutable!                    # setters raise ImmutableError after initialize
  frozen!                       # Ruby-freeze the instance at end of initialize (stackable with immutable!)
  coercion_policy :replace      # class-wide coercion-failure policy; inherited by subclasses
  unknown_attributes :raise     # reject unknown input keys (default :ignore = drop them)

  required :title, :string
  required :slug,  :string

  serialize :json, title: 'docTitle'   # map internal field -> external JSON key (:json wired in)

  validate :slug_matches_title         # cross-field validator (method symbol)
  validate { |rec| rec.errors.add(:base, 'empty') if rec.title.to_s.empty? }  # or block

  def slug_matches_title
    errors.add(:base, 'slug/title mismatch') unless slug == title.downcase
  end
end
```

- `coercion_policy` / `unknown_attributes` are read with no arg, set with one.
- **Inheritance:** all four macros inherit to subclasses; a child overrides by re-declaring, and the override never mutates the parent. `coercion_policy`/`unknown_attributes` override to any value; `immutable!`/`frozen!` are **one-way** — a child can add them but can't un-set an inherited one (no `mutable!`/`unfrozen!`).
- `validate` runs at `valid?` (and at construct if any exist); convention is `errors.add(:base, ...)`; `errors[:base]` is cleared each `valid?` run.

### Payment and API boundaries: `unknown_attributes :raise`

At a trust boundary (a payment request, a webhook, a partner API body) declare
`unknown_attributes :raise`. The default, `:ignore`, drops keys it doesn't know
without telling you. So a misspelled key (`"ammount"`) or a renamed field upstream
leaves a field unset, and a field you haven't modelled yet (`"cvv"`) goes away without
a trace. With `:raise`, `new` / `from_json` / `assign_attributes` / `with` fail with an
`UnknownAttributeError` whose `keys` name the extras (names only, never values).

- **Declare it on every struct that reads input**, nested ones too. It is inherited
  by *subclasses*, not by structs a field nests: a nested class without it still
  drops its own unknown keys. The nested error propagates out of the parent's
  `new` rather than going through the parent's `coercion_policy`.
- **`from_json` reverse-maps `serialize :json` names first**, so external names
  (`"amountDecimal"`) are known keys there. Passing them to `new` raises, because
  `new` takes canonical names.
- Keep `:ignore` where extra keys are expected and harmless, e.g. a struct reading
  a few fields out of a large third-party payload.

<!-- doctest -->
```ruby
class Card < FieldStruct::Base
  unknown_attributes :raise
  required :last4, :string
end

class Charge < FieldStruct::Base
  unknown_attributes :raise
  required :amount, :decimal
  required :card,   Card
  serialize :json, amount: 'amountDecimal'
end

Charge.from_json('{"amountDecimal":"9.99","card":{"last4":"4242"}}').valid?   # => true

typo = begin
  Charge.from_json('{"ammount":"9.99","card":{"last4":"4242"}}')
rescue FieldStruct::UnknownAttributeError => e
  e
end
typo.keys      # => [:ammount]
typo.message   # "unknown attribute(s) for Charge: :ammount"

nested = begin
  Charge.from_json('{"amountDecimal":"9.99","card":{"last4":"4242","cvv":"123"}}')
rescue FieldStruct::UnknownAttributeError => e
  e
end
nested.keys    # => [:cvv]
nested.message # "unknown attribute(s) for Card: :cvv"
```

---

## Instance surface

```ruby
u = User.new(name: 'Alice', age: '30')   # Hash arg; Symbol or String keys
u.name; u.age = 31                        # typed reader; permissive setter (coerces)
u.attributes        # => { name: "Alice", age: 31 }   (alias: to_h)
u.attribute_names   # => [:name, :age]
u.valid?            # runs cross-field validators, then errors.empty?
u.invalid?
u.errors            # FieldStruct::Errors
u.inspect           # #<User name: "Alice", age: 31>; an invalid instance appends
                    #   `errors: {name: ["is required"]}` so it never looks fine
u.model_name        # FieldStruct::ModelName (name/singular/plural/element); plural
                    #   just appends "s": Address → "addresss", Person → "persons"
u == other          # value equality (same class + same attributes; errors ignored)
u.as_json           # JSON-ready Hash with :json mapping applied
u.to_json           # String (via Oj)
User.from_json(str) # parse + reverse-map :json keys -> instance
u.assign_attributes(age: 40)              # bulk update through the setter pipeline
u.with(age: 41)                           # NEW instance with age changed; u untouched
case u; in { name: 'Alice', age: } then age; end   # pattern matching
```

### Copying with changes (`with`)

`with(**changes)` returns a new instance of the receiver's class with the given
attributes changed, like `Data#with`. The receiver is never modified, so it is the
way to "update" an `immutable!` or `frozen!` instance.

- **Changed fields go through the setter pipeline**: coercion, the field's
  `coercion_policy` (under `:raise` the `CoercionError` propagates and no copy is
  returned), and that field's errors rewritten. Cross-field `validate` blocks rerun.
- **Unchanged fields are carried over as they are**, errors included, exactly as
  `dup` copies them. Callable defaults are not called again.
- **Shallow**, like `dup`: an unchanged nested struct or array is the *same object*
  in both instances. Mutating one through the other is visible in both.
- **Unknown keys** follow `unknown_attributes` (dropped by default, `UnknownAttributeError`
  under `:raise`). String keys work too: `with('age' => 41)`.
- **Keywords only**: `with({age: 41})` raises `ArgumentError`; splat a Hash with
  `with(**hash)`. `with` with no changes returns an equal copy, not `self`.
- The copy is immutable when the class is, and frozen when the receiver is
  frozen. `with` (and `dup`, which it relies on) are reserved field names.

<!-- doctest -->
```ruby
class Point < FieldStruct::Base
  immutable!
  required :x, :integer
  required :y, :integer
end

origin = Point.new(x: 0, y: 0)
moved  = origin.with(x: '5')
moved.x                         # => 5
origin.x                        # => 0
moved.class                     # => Point
origin.with(y: nil).valid?      # => false
origin.valid?                   # => true
```

`Errors` API: `errors[:field] # => Array<String>`, `errors.add(:field, 'msg')`,
`errors.clear(:field)`, `errors.empty?`, `errors.to_h` (alias `messages`),
`errors.full_messages` (each message as a sentence — humanized field name
prepended, e.g. `first_name`/`is required` → `"First name is required"`; `:base`
messages pass through unprefixed).

---

## Validation semantics (important)

- **Per-field, on every assignment.** The setter owns its field's errors — it clears
  and rewrites `errors[name]` each time you assign.
- **Required + missing** → `errors.add(name, 'is required')`.
- **Present but invalid** → `errors.add(name, 'is invalid')`. "Invalid" = `format:`
  regex mismatch, `enum:`/`in:` violation, an invalid nested struct, or an array with
  an invalid element. An array element breaking its `element:` `format:`/`enum:`/`in:`
  is reported by index: `'element at index 2 is invalid'`. So **"required" means present *and* valid**.
- **Validity is separate from construction.** A field can hold `nil`/raw even when
  required — see coercion policy below. Always gate on `valid?`, don't assume a
  required reader is non-nil.

### Validity is computed on assignment (shallow `valid?` staleness)

A field's errors are written when *that field* is assigned, and `valid?` only reads
them (it reruns cross-field `validate` blocks, nothing else). A parent records an
invalid nested struct or array element when the nested value is assigned. **It
doesn't watch it afterwards.** Mutating a nested struct, or an array element, in
place leaves the parent's errors as they were, in both directions:

- the parent stays `valid?` after a nested field is broken in place, and
- stays invalid after a nested problem is fixed in place.

Pushing onto an array in place (`record.tags << 5`) also skips coercion: the raw
value is stored as-is.

**Workaround: assign the field again** (or use `with`/`assign_attributes`, which go
through the setter). That reruns coercion and validation for that field.

<!-- doctest -->
```ruby
class Address < FieldStruct::Base
  required :city, :string
end

class Person < FieldStruct::Base
  required :address, Address
  optional :tags,    :array, of: :string
end

person = Person.new(address: { city: 'Provo' })
person.address.city = nil         # mutate the nested struct in place
person.address.valid?             # => false
# Stale: the parent never saw the change.
person.valid?                     # => true

person.address = person.address   # re-assign: the setter re-validates
person.valid?                     # => false
person.errors[:address]           # => ['is invalid']

person.address.city = 'Provo'     # fixed in place...
# ...and stale the other way.
person.valid?                     # => false
person.with(address: person.address).valid?   # => true

person.tags = ['a']
person.tags << 5                  # in-place push: no coercion
person.tags                       # => ['a', 5]
person.tags = person.tags         # re-assign coerces each element
person.tags                       # => ['a', '5']
```

For a nested struct you mutate often, keep it `immutable!` (or `frozen!`) and use
`with` to change it. Then the only way to change it goes through a setter.

### Coercion failure policy

When a value can't be coerced into the field's type:

| Policy | Stored value | Error added | Notes |
|--------|--------------|-------------|-------|
| `:keep_raw` (default) | the raw input | yes (`could not be coerced: …`) | nothing lost; inspect & fix |
| `:replace` | `nil` | yes | clean slate |
| `:raise` | — | — | raises `FieldStruct::CoercionError` |

Messages name the field, the expected type and the input's *class*, never the value:
`could not be coerced: Integer fields expect a base-10 integer, got a String that is
not one`; under `:raise`, `could not coerce String input for cents: …`.

### Log safety: error messages and sensitive fields

Payments data must not reach a log line, so **no message FieldStruct builds echoes an
input value** — not an `errors` entry, not a raised error (`CoercionError`, a type's
`ArgumentError`/`TypeError`, `from_json`'s errors), and not their `cause` chain, which
error reporters print. Kernel conversion errors (`invalid value for Integer(): "…"`)
are dropped from the chain; an invalid-JSON error from `from_json` keeps Oj's error
class and position but not the quoted input. Declared schema (a format, a boolean's
accepted strings, a field name) is still named. A custom type owns its own messages:
raise with the value's class, not its `inspect`.

`sensitive: true` (any type, `true`/`false` only) masks the value where objects get
logged — `inspect`, and so `pp`, the `errors:` suffix of an invalid instance, nested
structs and arrays of them. `nil` still shows, so a missing value stays visible:

<!-- doctest -->
```ruby
class Card < FieldStruct::Base
  required :number, :string, sensitive: true
  optional :cvv,    :string, sensitive: true
  optional :brand,  :string
end

card = Card.new(number: '4111111111111111', brand: 'visa')
card             # => #<Card number: [FILTERED], cvv: nil, brand: "visa">
card.inspect.include?('4111')      # => false
card.number      # => "4111111111111111"
card.to_h        # => { number: "4111111111111111", cvv: nil, brand: "visa" }
Card.metadata[:number].sensitive?  # => true
```

Data paths are **not** masked — the reader, `attributes`/`to_h`, `as_json`/`to_json`,
`deconstruct_keys` and equality all return the real value, so `from_json(to_json)`
still round-trips. Masking there would corrupt the data; filter at the log boundary
if you log those. `Field#inspect`, `Metadata#to_h` (`sensitive: true`) and `describe`
show the flag only when it is set.

---

## Nested, arrays, unions

```ruby
class Address < FieldStruct::Base
  required :city, :string
end

class Person < FieldStruct::Base
  required :name,    :string
  optional :address, Address                 # nested: Hash or Address instance
  optional :aliases, :array, of: :string      # array of scalars
  optional :homes,   :array, of: Address       # array of nested (each coerced + validated)
  required :id,      :union, of: %i[string integer]   # union: first member that accepts it
end

Person.new(name: 'A', address: { city: 'NYC' }).address   # => #<Address city: "NYC">
```

Nested validity propagates: a `Person` with an invalid `address` is itself invalid.
Pattern matching recurses (`in { address: { city: 'NYC' } }`).

A refused array element is named by its index (0-based), never its value:
`errors[:ids] # => ["could not be coerced: element at index 1: Integer fields expect a base-10 integer, got a String that is not one"]`.
When several are refused, every index is listed and the first one's reason is
shown — `elements at index 1, 4, 7 (index 1 shown): …` — up to five indexes, then
a count (`elements at index 0, 1, 2, 3, 4 and 15 more (index 0 shown): …`). The
same message reaches every `coercion_policy`, `:raise` included.

### Element options (`element:`)

`element:` takes the options a scalar field of the element type would take, and
applies them to every element — coercion options (`strict:`, `base:`, `round:`,
`format:`, `zone:`, `values:`) and validation options (`format:` Regexp, `enum:`,
`in:`) alike. Array-level options stay on the field (`required:`, `default:`,
`coercion_policy:`, `sensitive:`, …).

<!-- doctest -->
```ruby
class Batch < FieldStruct::Base
  optional :ids,   :array, of: :integer, element: { strict: true, base: 16 }
  optional :days,  :array, of: :date,    element: { format: '%d/%m/%Y' }
  optional :codes, :array, of: :string,  element: { format: /\A[A-Z]{3}\z/ }
end

Batch.new(ids: %w[ff 10]).ids                    # => [255, 16]
Batch.new(ids: [1, 2.5]).errors[:ids]            # => ["could not be coerced: element at index 1: Integer fields with strict: true expect a whole number, got a Float that is not one"]
Batch.new(codes: %w[USD eur]).errors[:codes]     # => ["element at index 1 is invalid"]
Batch.new(codes: %w[usd EUR gbp]).errors[:codes] # => ["elements at index 0, 2 are invalid"]
Batch.new(ids: [1.5, 2, 'x']).errors[:ids]       # => ["could not be coerced: elements at index 0, 2 (index 0 shown): Integer fields with strict: true expect a whole number, got a Float that is not one"]
Batch.new(days: ['22/10/2026']).as_json[:days]   # => ['22/10/2026']
Batch.metadata.to_h[:ids][:options]              # => { of_type: 'Integer', element: { strict: true, base: 16 } }
```

They are checked at declaration against the element type's own schema, with the
error a scalar field would get, prefixed with the field: `element: { base: '16' }`
raises `in element: of array field :ids, base: on Integer expects Integer, got String
("16")`. A key the element type doesn't take raises, listing the ones it does
(`round: is not an Integer option. Integer accepts: in, base, strict.`) — unlike a
field, `element:` passes nothing through. A temporal element's `format:` is also
what `to_json` writes, so `from_json` reads it back. `describe` lists what each
array's elements accept, by name (`element accepts in, base, strict`); the shapes
are the element type's own (`FieldStruct::Types::Integer.option_schema`).
Not supported: `element:` on an `:array` of arrays, and on a nested struct element
(a struct takes no options).

---

## JSON & serialization

- `as_json`/`to_json` apply the `:json` `serialize` mapping (forward); `from_json`
  reverse-maps. Round-trips for every base type **except `:value`** (no type info to
  restore).
- Conversions in `as_json`: `Date`/`Time`/`DateTime` → ISO-8601 (or the field's
  `format:`), `BigDecimal` → plain string, `Symbol` → String, arrays/nested recurse.
- `from_json` parses JSON numbers with a fraction or exponent as `BigDecimal`, so a
  `:decimal` gets the exact digits sent (`1234567890123.4567`, not `…123.46`).
  `:float` still holds a Float; a `:value` field (and numbers inside its Hashes and
  Arrays) holds the `BigDecimal` — which `to_json` writes back as a string.

<!-- doctest -->
```ruby
class U < FieldStruct::Base
  required :first, :string
  serialize :json, first: 'firstName'
end
U.new(first: 'Al').to_json          # => '{"firstName":"Al"}'
U.from_json('{"firstName":"Al"}')   # => #<U first: "Al">
```

What the output holds:

- `as_json` returns a Hash with **Symbol** keys (after the mapping); `to_json` is
  that Hash as a String.
- **Every** field is written, in declaration order. An optional field you never
  set is `nil` in `as_json` and `null` in `to_json`, not left out.
- There is no per-call `only:` / `except:`: both methods ignore their argument.
  To leave a field out (say, a `sensitive:` one), filter the Hash yourself and
  dump it with Oj.

<!-- doctest -->
```ruby
class Card < FieldStruct::Base
  required :last4,    :string
  optional :nickname, :string
  optional :token,    :string, sensitive: true
end
card = Card.new(last4: '4242', token: 'tok_1')
card.as_json                     # => { last4: '4242', nickname: nil, token: 'tok_1' }
card.to_json                     # => '{"last4":"4242","nickname":null,"token":"tok_1"}'
card.to_json(only: [:last4])     # => '{"last4":"4242","nickname":null,"token":"tok_1"}'
Oj.dump(card.as_json.except(:token), mode: :compat)  # => '{"last4":"4242","nickname":null}'
```

---

## Custom types & namespaces

A namespace exposes `self.field_types` (a registry parented to the base set); fields
declared on classes inside that namespace resolve names through it.

```ruby
module Acme
  def self.field_types
    @field_types ||= FieldStruct.new_registry do   # parent defaults to FieldStruct.types
      register :money, Acme::Types::Money           # add a type
      register :dec,   :big_decimal                 # alias to an existing name
    end
  end

  class Invoice < FieldStruct::Base
    required :total, :money     # resolved via Acme.field_types
  end
end
```

A custom type is a `FieldStruct::Types::Base` subclass implementing `#coerce` and
`#ruby_type` (override `#missing?` for a broader notion than nil-only).

Optional short alias: `FieldStruct.use_alias!(:FS)` defines top-level `FS` →
`FieldStruct` and switches inspect output to the short prefix.

---

## Introspection

```ruby
User.metadata            # => #<FieldStruct::Metadata fields=[:name, :age]>
User.metadata[:age]      # => #<FieldStruct::Field :age Integer>
User.attribute_names     # => [:name, :age]
field = User.metadata[:age]
field.name; field.type; field.required?; field.default; field.options; field.type_instance.ruby_type
```

`metadata.to_h` gives each field as a plain Hash of strings and primitives, for
reading in a console. Classes and type objects in options are shortened to their
type name, so an array of structs shows `of_type: "Nested"` — **without** the
struct's class. A single nested field does name it, in `ruby_type`. To get the
element class of an array, read the live option instead:

<!-- doctest -->
```ruby
class Address < FieldStruct::Base
  optional :city, :string
end

class Person < FieldStruct::Base
  optional :home,  Address
  optional :addrs, :array, of: Address
end

Person.metadata.to_h[:home][:ruby_type]            # the class name: "Address"
Person.metadata.to_h[:addrs][:options]             # => { of_type: "Nested" }
Person.metadata[:addrs].options[:of_type].struct_class  # => Address
```

---

## RBS for your own classes

Sord types the library; `FieldStruct::RBS.generate` types the accessors **your**
`field` declarations create, so Steep/Solargraph can check `order.items`:

```ruby
class Order < FieldStruct::Base
  required :id,     :uuid
  optional :items,  :array, of: LineItem
  optional :status, :union, of: %i[symbol boolean]
  optional :scope,  :value, rbs_type: '::ActiveRecord::Relation'
  optional :extra,  :value
end

puts FieldStruct::RBS.generate(Order)
# # Generated by FieldStruct::RBS. Types describe a valid instance: an
# # invalid one (a required field left unset, or a :keep_raw coercion
# # failure holding the raw input) can hold other values. Check valid?.
# class Order < ::FieldStruct::Base
#   attr_reader id: ::String
#   def id=: (::String? value) -> ::String?
#
#   attr_reader items: ::Array[::LineItem]?
#   def items=: (::Array[::LineItem]? value) -> ::Array[::LineItem]?
#
#   attr_reader status: (::Symbol | bool)?
#   def status=: ((::Symbol | bool)? value) -> (::Symbol | bool)?
#
#   attr_reader scope: ::ActiveRecord::Relation?
#   def scope=: (::ActiveRecord::Relation? value) -> ::ActiveRecord::Relation?
#
#   attr_reader extra: untyped
#   def extra=: (untyped value) -> untyped
# end
```

- **Types describe a valid instance.** Reader = the field's Ruby type; nullability
  follows `required?` (required → `T`, optional → `T?`). An invalid instance (unset
  required field, `:keep_raw` failure holding raw input) can hold other values.
- **Writer** is `(T? value) -> T?` — the setter takes `nil` and returns the coerced
  value. Loose input it would coerce (`user.age = "30"` on an `:integer` field) runs
  fine but is a Steep error; coerce at the boundary.
- **Generics are filled in:** `::Array[::LineItem]` (a scalar element is nullable: `of: :string` → `::Array[::String?]`, because `["x", nil]` is valid), unions `(A | B)` (boolean →
  `bool`), nested structs by qualified name. A custom type whose `ruby_type` is a bare
  generic (`::Hash`) emits `::Hash[untyped, untyped]` unless the type defines
  `rbs_type` (`def rbs_type = '::Hash[::Symbol, ::String]'`).
- **`:value`** (and a union with a `:value` member) is `untyped`, reader and writer.
- **`rbs_type:`** (field) beats the type's `rbs_type`, which beats the derived type.
  It replaces `T` verbatim — `?` is still added for optional readers and all
  writers, and a union override is parenthesized first. Must be a non-blank String
  (checked at declaration; not parsed — `rbs` isn't a runtime dependency). Fully
  qualify constants (`::ActiveRecord::Relation`).

`FieldStruct::RBS.type_for(field, nullable: nil)` returns one field's type exactly as
`generate` emits it, for generators that type methods taking or returning the field:

```ruby
FieldStruct::RBS.type_for(Order.metadata[:items])                  # => "::Array[::LineItem]?"
FieldStruct::RBS.type_for(Order.metadata[:items], nullable: false) # => "::Array[::LineItem]"
FieldStruct::RBS.type_for(Order.metadata[:id], nullable: true)     # => "::String?"
```

`nullable: nil` (default) follows `!field.required?`; `untyped` never gets `?`.
Generate RBS for nested/element classes too so `::LineItem` references resolve. See
the README "Type signatures" section for a Rake-task wiring example.

## JSON Schema for your own classes

`FieldStruct::JSONSchema.generate(klass)` (or `Klass.to_json_schema`) returns a
JSON Schema (draft 2020-12) of the JSON the class writes with `to_json` and reads
back with `from_json`: for API docs, other-language validators, LLM tool
parameters (RubyLLM takes any object responding to `to_json_schema`), TypeScript
types. It returns a Hash with String keys; `Oj.dump` it. No dependency.

<!-- doctest -->
```ruby
class Pet < FieldStruct::Base
  required :name, :string, description: 'Call name'
  optional :born, :date
end

class Owner < FieldStruct::Base
  required :first_name, :string
  optional :plan, :string, enum: %w[free pro], default: 'free'
  optional :age,  :integer, in: 0..150
  optional :pets, :array, of: Pet
  serialize :json, first_name: 'firstName'
end

schema = Owner.to_json_schema
schema['type']                    # => "object"
schema['required']                # => ["firstName"]
schema['properties']['firstName'] # => {"type" => "string"}
schema['properties']['age']       # => {"type" => ["integer", "null"], "minimum" => 0, "maximum" => 150}
schema['properties']['plan']['default']             # => "free"
schema['properties']['plan']['anyOf'].first         # => {"type" => ["string", "null"], "enum" => ["free", "pro", nil]}
schema['properties']['pets']['items']['anyOf'].first.keys  # => ["$ref"]
schema['$defs'].values.first['properties']['born']  # => {"type" => ["string", "null"], "format" => "date"}
```

- **It describes the canonical JSON, not every input the setters coerce.**
  `age: "30"` is a fine assignment but not valid against `"type": "integer"`.
  BigDecimal is a decimal string (`"pattern": "^-?[0-9]+\\.[0-9]+$"`, as `to_json`
  writes it); dates are `"format": "date"`, times and datetimes `"date-time"`
  (only for the default or `:iso8601` format: a `:db`, `:rfc2822` or strftime
  format is a plain string); `:value` is `{}` (anything).
- **`:uuid`, `:url`, `:email`** are described by the Regexp the struct checks:
  the default UUID one is `"format": "uuid"`; the URL and Email defaults become
  a `pattern`, because JSON Schema's `uri` and `email` are stricter than ours
  (`josé@example.com` passes the struct, fails `email`). An `:array, of: :uuid`
  checks nothing per element unless `element: { format: … }` says so, and its
  schema says the same.
- **Property names** are the `serialize :json` names; `generate(klass,
  serialization: :xml)` uses another format's.
- **`required`** lists required fields without a `default:` (a default fills a
  missing key). Optional fields also accept `null`, and so does every array
  element, nested ones too (validation skips `nil` elements). An optional
  string field with `enum:` or a `format:` also accepts a blank string: blank
  counts as missing there, so the struct is valid and `to_json` writes `""`.
- **Constraints:** `enum:` → `enum`; `in:` Range → `minimum` / `maximum` /
  `exclusiveMaximum` (an infinite end stays open), `in:` Array → `enum`; a
  Regexp `format:` → `pattern`. `FieldStruct::JSONSchema.pattern_for(regexp)`
  translates it to an ECMA-262 pattern that matches the same strings, with or
  without the `u` flag: `\A` / `\z` → `^` / `$`, `.` and `\s` keep Ruby's
  meaning, `/i` is spelled out (`ok` → `[oO][kK]`). A Regexp with no exact
  translation (possessive quantifiers, atomic groups, `\p{…}`, POSIX brackets,
  `/x`) becomes `x-ruby-pattern` with the Ruby source: an annotation, not
  checked by validators, and more Regexps may translate in later versions.
  `in:` on dates, times and decimals has no keyword and is left out.
- **Nested structs** go in `$defs` under their class name and are referenced with
  `$ref`; the root itself is `#`, so recursive structs work. An anonymous nested
  struct is inlined, and so is one named under an anonymous module.
- **Annotations:** `description:` → `description`; a `default:` that is
  already what `to_json` writes → `default` (a callable, or `default: 1` on a
  string field, is left out); `sensitive: true` → `x-sensitive`
  (`to_json` still writes the value). `unknown_attributes :raise` →
  `"additionalProperties": false`.
- **Overrides:** a field's `json_schema: {...}` option beats the type's
  `json_schema` method (define it on a custom type: `def json_schema = {'type' =>
  'string'}`), which beats the derived schema. A custom type with neither is
  unconstrained and named: `{"x-ruby-type" => "Money"}`. An override describes
  a present value: an optional field still adds `null`.
- **The Hash is a fresh copy:** add enum values or descriptions for an LLM tool
  without touching the class.

---

---

## Gotchas / invariants

- **Setters are permissive by design** — `user.age = "30"` is valid (coerces). The
  generated writer is typed `(T? value) -> T?`, so Steep flags that line even though
  Ruby accepts it.
- **A required field can still be `nil`** (coercion failed under `:keep_raw`/`:replace`,
  or never assigned). Check `valid?`; don't assume required ⇒ non-nil.
- **Whitespace-only strings are "missing"** for `:string` and its subclasses
  (`:uuid`/`:url`/`:email`/`:immutable_string`). `:binary` is the exception — its
  whitespace bytes are real data, so only nil/empty count as missing.
- **`nil` passes through coercion as `nil`** for essentially every type.
- **Temporal coercion behaves the same with or without ActiveSupport loaded.**
  That is a deliberate invariant, not a coincidence — see `.claude/project_intent.md`
  invariant 7. Coercion dispatches on explicit stdlib classes rather than on
  `respond_to?(:to_date)` and friends, which ActiveSupport defines on every String.
- `:array` requires `of:`; `:union` requires `of: [...]` with ≥2 members. Options for
  each array element go in `element: { ... }`, not on the field.
- Option scoping: `format:` → string-shaped + date/time/datetime; `enum:` →
  string/symbol; `in:` → integer/float/decimal/date/time/datetime; `round:` →
  float/decimal; `base:` → integer; `strict:` → string-shaped/integer; `values:` → boolean; `element:` → array. Misapplying raises `ArgumentError` at declaration.
- `description:`/`desc:` is documentation only — absent from `attributes`, `as_json`,
  and pattern-match keys.
- **Input is a Hash, or anything with `to_hash`** (e.g. a permitted
  `ActionController::Parameters`). `new(nil)` is the same as `new`; any other
  shape (`new([])`, `new("x")`, `assign_attributes(nil)`) raises `ArgumentError`
  naming the class it got.
- **`dup` / `clone` copy the errors too** — the copy starts with the original's
  messages but owns them, so changing one's top-level fields never changes the
  other's `valid?`. The copy is shallow: nested structs are shared.
- **Some field names are reserved** — the ones `Base` calls on its own instances
  (`errors`, `attributes`, `hash`, `class`, `send`, `to_h`, `inspect`, … — see
  `FieldStruct::Base::RESERVED_FIELD_NAMES`). Declaring one raises `ArgumentError`
  naming it; name the field something else and map the external key with
  `serialize :json, errors_field: 'errors'`. `method`, `name`, `type` stay legal.
- Unknown input keys are dropped by default (`unknown_attributes :ignore`); set
  `:raise` to reject them with `UnknownAttributeError` — recommended at payment/API
  boundaries, on each struct (see [above](#payment-and-api-boundaries-unknown_attributes-raise)).
- **Validity is computed on assignment.** In-place mutation of a nested struct or an
  array element doesn't refresh the parent's errors; re-assign the field (see
  [staleness](#validity-is-computed-on-assignment-shallow-valid-staleness)).
- Uses **Oj** for JSON (`Oj.load`/`Oj.dump`), not the stdlib JSON.
