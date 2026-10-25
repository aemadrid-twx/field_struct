# FieldStruct

Typed POROs for Ruby — declare fields with enforced types, presence checks, and per-field validation. Mirrors the ActiveModel interface shape where it helps adoption, but reuses none of its code.

<!-- doctest -->
```ruby
class User < FieldStruct::Base
  required :name, :string
  optional :age,  :integer
  optional :tags, :array, of: :string
end

u = User.new(name: 'Alice', age: '30', tags: %w[admin staff])

u.name        # => "Alice"
u.age         # => 30
u.tags        # => ["admin", "staff"]
u.valid?      # => true
u.attributes  # => { name: "Alice", age: 30, tags: ["admin", "staff"] }
u.to_json     # => '{"name":"Alice","age":30,"tags":["admin","staff"]}'

u.name = ''
u.valid?               # => false
u.errors[:name]        # => ["is required"]
u.errors.full_messages # => ["Name is required"]
```

`inspect` surfaces invalidity too: a valid instance reads cleanly
(`#<User name: "Alice", age: 30, …>`), while an invalid one appends its errors —
`#<User name: "", age: 30, … errors: {name: ["is required"]}>` — so an object
never *looks* fine when it isn't.

## Installation

Add it to your Gemfile from [RubyGems](https://rubygems.org/gems/field_struct):

```ruby
gem 'field_struct'
```

or run `bundle add field_struct`.

Requires Ruby 3.3+.

Upgrading from an earlier version? [`UPGRADING.md`](UPGRADING.md) lists every visible change, how to find the code it affects, and the fix.

> **New here?** [`docs/getting_started.md`](docs/getting_started.md) walks through
> using FieldStruct in a repo (general Ruby + a Rails section). For the exhaustive
> reference, [`USAGE.md`](USAGE.md) is a dense, example-first cheat sheet — every type,
> option, and macro on one page. Both ship with the gem (`bundle show field_struct`),
> for editors and AI assistants to read.

## What FieldStruct is

- A typed-value-object foundation: declare attributes, get coercion + validation for free.
- A class-level `Metadata` collection per FieldStruct class, inspectable and introspectable.
- A pluggable type system, namespaced through a `Registry` that downstream code can extend or replace.
- ActiveModel-shaped at the public surface (`valid?`, `errors`, `attributes`, `as_json`, `to_json`, `model_name`, `to_model`) so Rails-adjacent code feels at home.

## What FieldStruct is not

- Not a database layer. It doesn't persist, query, or hold connections.
- Not a form object. It doesn't render or know about HTTP params.
- Not an ActiveModel replacement. Interface shape only — no AM code reuse.
- Not a hash-schema validator. Validation is per-field-on-assignment, not "check this hash against a schema."

## Declaring fields

Three macros declare fields; `field` is the primitive, `required` / `optional` are sugar that set the `required:` option.

```ruby
class Account < FieldStruct::Base
  field    :id,         :integer                    # neutral; defaults to optional
  required :email,      :string, format: /@/        # presence-checked + format
  optional :nickname,   :immutable_string           # coerced, then frozen
  optional :balance,    :decimal, default: '0'      # :decimal is an alias for :big_decimal
  optional :created_at, :datetime
  required :tags,       :array, of: :string         # element type is required
end
```

### Base types

`:string`, `:immutable_string`, `:integer`, `:float`, `:big_decimal` (aliased as `:decimal`), `:boolean`, `:date`, `:time`, `:datetime`, `:value`, and `:array` (parameterized via `of:`).

Extended types: `:symbol`, `:uuid`, `:url`, `:email`, `:binary`. The first four serve string-shaped use cases — `:uuid`/`:url`/`:email` pre-fill a sensible `format:` regex (overrideable per-field), `:binary` forces ASCII-8BIT encoding and treats whitespace bytes as meaningful (not "missing").

`:value` is a passthrough — useful when you want metadata for a field without committing to a shape.

### Union types

A field that may hold any of several types — each tried in declared order, first success wins:

```ruby
class Event < FieldStruct::Base
  optional :payload, :union, of: [Payload, :boolean]
  optional :id,      :union, of: %i[integer string]
end

Event.new(payload: { kind: 'click', value: 1 }).payload  # => #<Payload ...>
Event.new(payload: true).payload                          # => true
Event.new(id: '42').id                                    # => "42"   (string first)
```

Members can be Symbols (registered scalars or FieldStruct subclasses) or Class arguments (FieldStruct subclasses). If every member rejects the value, the union raises and the parent's `coercion_policy` engages. Declared order matters — pick deliberately when types overlap (`Integer` accepts `"42"`, `String` accepts `"42"` — the one listed first wins).

### Nested FieldStructs

Pass a `FieldStruct::Base` subclass as the type to nest:

```ruby
class Address < FieldStruct::Base
  required :street, :string
  required :city,   :string
end

class Person < FieldStruct::Base
  required :name,      :string
  required :address,   Address
  optional :addresses, :array, of: Address     # arrays of nested too
end

Person.new(name: 'Alice', address: {street: '1', city: 'NYC'}).address
# => #<Address street: "1", city: "NYC">
```

- Accepts nil / a struct instance / a Hash (`Address.new(hash)` happens automatically).
- If the nested struct is invalid at assignment time, the parent gets `errors[:address] = ['is invalid']`. Drill into `parent.address.errors` for the per-field breakdown.
- Validity is computed **on assignment**. Mutating a nested struct (or an array element) in place doesn't refresh the parent's errors; assign the field again, or use `with`, to re-validate. See [USAGE: shallow `valid?` staleness](USAGE.md#validity-is-computed-on-assignment-shallow-valid-staleness).
- Inner construction errors (e.g. `FieldStruct::UnknownAttributeError` from a nested class with `unknown_attributes :raise`) propagate to the caller rather than being caught by the parent's `coercion_policy`.
- `as_json` / `to_json` deep-walk nested structures.

### What "required" means

A required field is invalid when its **value** is missing after coercion — the *type* decides what "missing" means:

| Type | Missing if |
|---|---|
| `:string`, `:immutable_string` | nil, empty, or whitespace-only |
| `:integer`, `:float`, `:decimal` | nil only (`0` is valid) |
| `:boolean` | nil only (`false` is valid) |
| `:date`, `:time`, `:datetime` | nil only |
| `:array` | nil or empty |
| `:value` | nil only |

Defaults satisfy required — the value is what's checked, not whether the input hash contained the key.

`default:` accepts a literal or any callable (Proc, Lambda, Method) that takes no arguments. The callable is invoked once per instance, so it's safe to use for per-instance values like timestamps or generated IDs:

```ruby
optional :created_at, :datetime, default: Time.method(:now)
optional :token,      :string,   default: -> { "tok-#{SecureRandom.hex(4)}" }
```

### Documenting fields with `description:` / `desc:`

Attach a human-readable description to each field for downstream documentation generators. Aliased — pick whichever reads better at the call site:

```ruby
class User < FieldStruct::Base
  required :email,      :string,  description: 'Primary contact address'
  required :first_name, :string,  desc: 'Given name'
  optional :age,        :integer
end

User.metadata[:email].description  # => 'Primary contact address'
User.metadata[:email].desc         # => same
User.metadata[:age].description    # => nil
```

The description is documentation metadata — it does **not** appear in `attributes` / `as_json` / `to_json` / pattern matches. Downstream gems can walk `Klass.metadata` to emit docs in any format. Passing both `description:` and `desc:` to the same field raises `ArgumentError`.

### Per-type field options

Each type accepts a small set of customization options at the field level. Values can be literals or Symbol presets (resolved at class-load time against the type's `presets` Hash).

```ruby
class Order < FieldStruct::Base
  required :total,        :decimal,  round: 2                  # round to 2 decimals
  required :discount,     :float,    round: 4
  required :sku_hex,      :integer,  base: 16                 # "1A" → 26 (strings default to base 10)
  required :paid,         :boolean,  values: :english_yes_no   # symbol preset
  required :priority,     :boolean,  values: {truthy: %w[high urgent], falsy: %w[low normal]}
  required :placed_at,    :datetime, format: :db               # '%Y-%m-%d %H:%M:%S'
  required :ship_by,      :date,     format: '%m/%d/%Y'        # explicit strftime/strptime
  required :customer_id,  :uuid,     format: :v4               # v4-only regex
  required :contact,      :email,    format: :strict           # stricter regex preset
  required :cents,        :integer,  strict: true              # 12.7 refused, not truncated
  required :starts_at,    :time,     zone: '-06:00'            # zone-less input read at -06:00
  optional :ids,          :array,    of: :integer, element: {strict: true}  # options for each element
end
```

Two field options work on any type: `sensitive: true` shows `[FILTERED]` in `inspect` / `pp` while readers, `to_h` and `to_json` keep the real value, and error messages never echo input values at all (see [Log safety](USAGE.md#log-safety-error-messages-and-sensitive-fields)).

What each type supports:

| Type | Option | Form | Built-in presets |
|---|---|---|---|
| `:big_decimal` / `:decimal`, `:float` | `round:` | Integer (half up; result keeps the field's type) | — |
| `:integer` | `base:` | Integer 2..36 (string radix; default 10) | — |
| `:string` (and subtypes), `:integer` | `strict:` | Boolean — refuse loose input instead of `to_s` / truncating ([Strict coercion](USAGE.md#strict-coercion-strict-true)) | — |
| `:array` | `element:` | Hash of the element type's own options, applied to each element ([Element options](USAGE.md#element-options-element)) | — |
| `:time`, `:datetime` | `zone:` | `"UTC"`, `"±HH:MM"` or an IANA name (`"America/Denver"`, DST-aware) — the zone for zone-less input ([Zones](USAGE.md#zones-zone)) | — |
| `:boolean` | `values:` | `{truthy:, falsy:}` Hash, or Symbol | `:english_yes_no`, `:english`, `:numeric` |
| `:date` | `format:` | strftime String, or Symbol | `:iso8601`, `:us`, `:eu` |
| `:datetime`, `:time` | `format:` | strftime String, or Symbol | `:iso8601`, `:rfc2822`, `:db` |
| `:email` | `format:` | Regexp, or Symbol | `:permissive`, `:default`, `:strict` |
| `:uuid` | `format:` | Regexp, or Symbol | `:any_version`, `:v4`, `:v7` |
| `:url` | `format:` | Regexp, or Symbol | `:http`, `:https_only`, `:any_scheme` |

You don't have to memorize this table — **each type describes its own options at runtime**. `FieldStruct.types.lookup(:date).option_schema` returns `{ format: {type:, required:, presets:}, in: {...} }`. The DSL validates these native options at class-load: a wrong-shaped value (`round: '2'`) or a misapplied option (`enum:` on `:integer`) raises with the expected shape / the types it applies to. An option the type doesn't recognize is **not** an error — it's stored verbatim on the `Field`, so downstream tooling (e.g. an Avro exporter) can carry its own options.

Time-shaped `format:` applies in **both** directions: input strings parse via `strptime`, output (`as_json` / `to_json`) emits via `strftime`. The exception is `:iso8601`, which FieldStruct parses and renders itself as RFC 3339 (`Types::Rfc3339Format`) rather than through a strftime string — no strftime string can express an optional fractional second, and `%z` emits `+0000` where RFC 3339 requires `+00:00` or `Z`. The round-trip property holds either way — `Klass.from_json(instance.to_json) == instance` for any format you pick.

You can override the type's defaults class-wide by subclassing and overriding the relevant `default_*` or `presets` method, then registering the subclass:

```ruby
class USDate < FieldStruct::Types::Date
  def self.default_format = '%m/%d/%Y'
end

module Acme
  def self.field_types
    @field_types ||= FieldStruct.new_registry { register :us_date, USDate }
  end
end
```

Numeric coercion is strict about what a number is: `:integer` reads strings in base 10 (`"010"` is 10, `"0x1A"` is refused) unless the field declares `base:`; `:integer`, `:float` and `:decimal` refuse NaN and ±Infinity (including JSON `1e400`) as a coercion failure; and `round:` rounds half up whatever the global `BigDecimal.mode`, returning a `Float` / `BigDecimal` even at `round: 0`.

### Restricting values — `enum:` and `in:`

Two parallel options for "the coerced value must be one of these":

```ruby
required :status,    :string,  enum: %w[on off]
required :position,  :symbol,  enum: %i[before after]
required :page_size, :integer, in: [10, 20, 30]
required :amount,    :float,   in: 1.0..10.0
required :height,    :integer, in: (10..)   # parentheses: a bare `10..` at line end swallows the next line
required :start_on,  :date,    in: Date.new(2024, 1, 1)..Date.new(2024, 12, 31)
```

- `enum: [...]` — string-like types (`:string`, `:symbol`, `:uuid`, etc.). Array of allowed values.
- `in:` — rangy types (`:integer`, `:float`, `:decimal`, `:date`, `:time`, `:datetime`). An Array is a membership test; a Range is a bounds check via `cover?`, so closed and half-open both work and a `:date` / `:datetime` range compares endpoints instead of enumerating days.
- Both run post-coercion (`'10'` becomes `10` before the check) and emit `'is invalid'` on mismatch.
- Passing `enum:` to a rangy field — or `in:` to a string-like field — raises `ArgumentError` at class load.

## Class macros

Every macro is inherited by descendants and overridable.

### `coercion_policy`

What happens when a value can't be coerced into the declared type:

```ruby
class Strict < FieldStruct::Base
  coercion_policy :raise      # :keep_raw (default) | :replace | :raise
  required :age, :integer
end

Strict.new(age: 'abc')  # raises FieldStruct::CoercionError
```

- `:keep_raw` — store the raw uncoercible value, record `"could not be coerced: ..."`
- `:replace`  — store `nil`, record the same error
- `:raise`    — raise `FieldStruct::CoercionError` from the setter

A single field can override the class-level policy via `coercion_policy:`:

```ruby
class Mixed < FieldStruct::Base
  coercion_policy :keep_raw                       # class default
  required :strict_id, :integer, coercion_policy: :raise
  optional :lenient_count, :integer               # inherits :keep_raw
end
```

### `immutable!`

Block reassignment after construction. Default mutable.

```ruby
class Config < FieldStruct::Base
  immutable!
  required :api_key, :string
end

c = Config.new(api_key: 'sk-...')
c.api_key = 'oops'   # raises FieldStruct::ImmutableError
```

### `frozen!`

Make instances Ruby-frozen at the end of construction. Stricter than `immutable!` — any ivar mutation raises `FrozenError` (Ruby's mechanism, not ours).

```ruby
class FrozenConfig < FieldStruct::Base
  frozen!
  required :api_key, :string
end

c = FrozenConfig.new(api_key: 'sk-...')
c.frozen?     # => true
c.api_key = 'x' # => raises FrozenError
```

Independent of `immutable!` — pick `immutable!` for our custom error and check, `frozen!` for Ruby's built-in freeze. Both can stack.

### `unknown_attributes`

How `initialize` / `assign_attributes` respond to input keys that don't match any declared field:

```ruby
class Strict < FieldStruct::Base
  unknown_attributes :raise   # :ignore (default) | :raise
  required :name, :string
end

Strict.new(name: 'Alice', extra: 'x')  # raises FieldStruct::UnknownAttributeError
```

Use `:raise` at payment and API boundaries, on every struct that reads input (nested classes don't inherit it from the struct that holds them). Otherwise a misspelled or renamed key is dropped without a word. See [USAGE: Payment and API boundaries](USAGE.md#payment-and-api-boundaries-unknown_attributes-raise).

### Inheritance

All four macros inherit to subclasses. A child overrides one by re-declaring it; the override is isolated — it never changes the parent.

<!-- doctest -->
```ruby
class Account < FieldStruct::Base
  coercion_policy :raise
  immutable!
end

class GuestAccount < Account
  coercion_policy :keep_raw    # override — Account stays :raise
end

GuestAccount.coercion_policy   # => :keep_raw
Account.coercion_policy        # => :raise
GuestAccount.immutable?        # => true
```

| Macro | Inherited | Override on a child |
|---|---|---|
| `coercion_policy` | ✅ | any value |
| `unknown_attributes` | ✅ | `:ignore` ↔ `:raise` |
| `immutable!` | ✅ | can add, **not remove** (one-way; no `mutable!`) |
| `frozen!` | ✅ | can add, **not remove** (one-way; no `unfrozen!`) |

Because `immutable!` / `frozen!` tighten but don't loosen, put them on the leaf classes that need them — not a shared parent — if some subclasses must stay mutable.

## Namespace registries

Each FieldStruct class resolves type names through a registry chain. Define a module-level `field_types` method to extend the default set inside a namespace:

```ruby
module Acme
  def self.field_types
    @field_types ||= FieldStruct.new_registry do
      register :money, Acme::Types::Money
    end
  end

  class Order < FieldStruct::Base
    required :price, :money     # resolved through Acme's registry, with FieldStruct.types as fallback
  end
end
```

`FieldStruct.new_registry` builds a new registry parented to `FieldStruct.types` and evaluates the block in the new registry's instance scope, so `register` works without a receiver. Pass `nil` for an unparented registry, or a different parent for a custom chain.

Lookup walks the class's containing modules from innermost outward, then falls back to `FieldStruct.types`.

## Cross-field validation

For checks that span more than one field, declare a `validate` block or point to an instance method. Both forms can be mixed and stacked.

```ruby
class Schedule < FieldStruct::Base
  required :start_date, :date
  required :end_date,   :date

  validate :ensure_chronological
  validate do |record|
    record.errors.add(:base, 'must span at least one day') if record.end_date == record.start_date
  end

  def ensure_chronological
    return unless start_date && end_date

    errors.add(:base, 'end_date must not precede start_date') if start_date > end_date
  end
end

bad = Schedule.new(start_date: '2024-02-01', end_date: '2024-01-15')
bad.errors[:base]   # => ['end_date must not precede start_date', 'must span at least one day']
bad.valid?          # => false
```

- Validators run on `valid?` (and once at the end of `initialize`, so a fresh instance has `errors[:base]` populated for inspection).
- `errors[:base]` is cleared at the start of each cross-field run, so stale entries don't pile up.
- Field-level errors written by setters (Phase 1's "setter owns its field's errors") are **not** cleared by `valid?` — only `:base` is.
- Validators are inherited by subclasses (the subclass receives a `dup` of the parent's list and can append).
- Symbol form `validate :name, :other` registers each as its own validator.

## Serialization — bridging external naming conventions

When a payload arrives with names that don't match your Ruby conventions — `firstName` from a vendor API, `EMAIL_ADDR` from a legacy DB — declare a `serialize` block on the class. The mapping is internal-symbol → external-string and applies to both directions (import reverse-maps, export forward-maps).

```ruby
class User < FieldStruct::Base
  required :email,      :string
  required :first_name, :string
  required :last_name,  :string

  serialize :json,
            first_name: 'firstName',
            last_name:  'lastName'
end

# Import — JSON keys are reverse-mapped to canonical fields.
user = User.from_json('{"email":"a@b.com","firstName":"Alice","lastName":"Smith"}')
user.first_name  # => "Alice"

# Export — to_json applies the mapping forward.
user.to_json
# => '{"email":"a@b.com","firstName":"Alice","lastName":"Smith"}'

# Round-trip: User.from_json(user.to_json) == user.
```

- Fields not listed in the mapping (here `:email`) use their canonical name unchanged.
- `to_h` and `attributes` always return canonical names — only `to_json` / `as_json` / `from_json` consult the mapping.
- Each mapping key must be a declared field; an unknown key raises `ArgumentError` at class load. Declare fields first, then `serialize`.
- The mapping is inherited by subclasses; redeclaring on a subclass replaces it (last-write-wins).
- Nested FieldStructs apply their own mapping — including struct members of a `:union`. `from_json` tries the union's members in declared order, reverse-mapping the object through each struct member's mapping, so give struct members `unknown_attributes :raise` if the union must tell them apart.
- Multiple formats can coexist on the same class (`serialize :json, ...` + `serialize :csv, ...`). Only `:json` is wired in-gem; CSV / XML / Avro support is left for downstream gems that read `Klass.metadata.serializations[:their_name]`.
- Nested FieldStructs and arrays of nested propagate naturally — each level uses its own serialize mapping.

## Parsing JSON

`Klass.from_json(string)` parses with Oj and feeds the resulting hash through `.new` — so coercion, nested construction, `unknown_attributes`, and `coercion_policy` all engage the same way they do for direct calls. When the class has a `serialize :json` mapping, external keys are reverse-mapped to canonical names before construction.

```ruby
person = Person.from_json('{"name":"Alice","address":{"street":"1","city":"NYC"}}')
person.address.city  # => "NYC"

# Round-trips for every base type except :value (no type info to preserve).
restored = Person.from_json(person.to_json)
restored == person   # => true
```

A non-object root (`[...]`, `"hi"`, `42`, `null`) raises `ArgumentError`; malformed JSON propagates the underlying Oj parse error.

## Pattern matching

Every FieldStruct instance works as a Ruby 3.0+ pattern target out of the box. Hash patterns slice into the declared fields by canonical name; array patterns bind values in declaration order.

```ruby
case user
in { name: 'Alice', age: Integer => age }
  "Alice is #{age}"
in { age: ..18 }
  'minor'
in { name: }
  "found #{name}"
end

# Nested FieldStructs recurse naturally
case order
in { customer: { email: }, items: [_, *] }
  "order from #{email} with multiple items"
end

# Array pattern uses declared field order
case point   # required :x, :integer; required :y, :integer
in [x, y]
  Math.hypot(x, y)
end

# Find pattern over an array of nested
case team
in { members: [*, { role: :admin, name: } => _admin, *] }
  "admin: #{name}"
end
```

Aliases and `errors` do **not** participate in pattern matching — patterns are Ruby-side and use canonical field names. Frozen and immutable instances pattern-match the same way as mutable ones (reads only).

## ActiveModel-shaped surface

Mirroring AM's call sites so Rails-adjacent code feels at home:

```ruby
u = User.new(name: 'Alice')

u.valid?           # / u.invalid?
u.errors           # FieldStruct::Errors  ([] / add / clear / empty? / to_h / messages / full_messages)
u.attributes       # / u.attribute_names
u.assign_attributes(name: 'Bob')
u.with(name: 'Carol')  # a NEW instance with name changed; u untouched (like Data#with)
u.to_h             # alias of #attributes
u.as_json          # JSON-ready hash (Date/Time -> ISO-8601, BigDecimal -> string)
u.to_json          # via Oj
u.inspect          # #<User name: "Alice">  (appends `errors: {…}` when invalid)
u.model_name       # FieldStruct::ModelName  (name / singular / plural / element);
                   #   plural only appends "s" (Address → "addresss")
u.to_model         # self
u == other         # structural equality (class + attributes)
```

## Type signatures

The gem ships with RBS signatures at `sig/field_struct.rbs`, generated from YARD comments via [Sord](https://github.com/AaronC81/sord). Downstream code using Solargraph, Steep, or other RBS-aware tools gets type info for the public surface for free.

```bash
bundle exec rake sigs:generate   # regenerate from current YARD
bundle exec rake sigs:validate   # rbs validate everything under sig/
bundle exec rake sigs:check      # CI guard: error if sigs are stale
bundle exec rake sigs:untyped    # CI guard: untyped count must equal the committed ceiling
```

The generated file is committed to git. Improve YARD when you want to improve the sig — don't edit `sig/field_struct.rbs` by hand. Run `rake sigs:check` before pushing if you changed any YARD.

The sig can only get more typed. `sigs:untyped` fails when the non-comment `untyped` count in `sig/` rises above `rakelib/sig_guards/untyped_ceiling.txt`, and also when it falls below it — lower the ceiling in the same PR. `sigs:generate` / `sigs:check` fail on any Sord `[OMIT]` (no YARD type) or `[DUCK]` warning not listed in `rakelib/sig_guards/sord_allowlist.txt`, and on a listed one Sord no longer emits, so the list only shrinks. A report-only `steep check` runs in CI (`gemfiles/types.gemfile`, Ruby >= 3.3); it never fails the build.

Sord covers the **library** classes only. The per-field accessors that the `field` DSL defines on **your** subclasses (`user.name`, `user.age=`) don't exist until you declare the fields, so Sord can't see them — that's the other half of [D13](docs/origin/plan.md).

### Signatures for your own FieldStruct classes

`FieldStruct::RBS.generate` walks a subclass's metadata and emits RBS for its generated accessors, so Steep / Solargraph can type-check code that touches them:

```ruby
class User < FieldStruct::Base
  required :name, :string
  optional :age,  :integer
end

puts FieldStruct::RBS.generate(User)
# # Generated by FieldStruct::RBS. Types describe a valid instance: ...
# class User < ::FieldStruct::Base
#   attr_reader name: ::String
#   def name=: (::String? value) -> ::String?
#
#   attr_reader age: ::Integer?
#   def age=: (::Integer? value) -> ::Integer?
# end
```

The types describe a **valid** instance: readers carry the field's coerced Ruby type, with nullability from `required?` (required → `T`, optional → `T?`); an invalid instance can hold other values. Setters are `(T? value) -> T?` — they accept `nil` and return the coerced value. Arrays, unions and nested structs carry their element types (`::Array[::LineItem]`, `(::String | bool)`, `::Address`) — generate RBS for referenced classes too so they resolve. `:value` fields are `untyped`. Override a field's type with `rbs_type: '::ActiveRecord::Relation'`, or a custom type's with `def rbs_type`. `FieldStruct::RBS.type_for(field)` returns one field's type for other generators. Details and examples in [USAGE.md](USAGE.md#rbs-for-your-own-classes).

Wire it into your project with a Rake task that writes a sig file per class — for example:

```ruby
# lib/tasks/field_struct_rbs.rake
namespace :field_struct do
  desc 'Generate RBS for the app\'s FieldStruct classes'
  task rbs: :environment do
    classes = [User, Account, Order] # the FieldStruct subclasses you want typed
    File.write('sig/field_structs.rbs', classes.map { |k| FieldStruct::RBS.generate(k) }.join("\n"))
  end
end
```

## Scaffolding a class from JSON

`FieldStruct::Scaffold.from_json` turns a JSON example (or several) into starter FieldStruct source — handy when modeling an existing API or webhook. It's a **working prototype you refine**: it nails the structure and the obvious types and flags the rest with comments, leaving enums, descriptions, and final scalar types to you.

```ruby
puts FieldStruct::Scaffold.from_json(<<~JSON, class_name: 'User')
  {"name": "Al", "age": 30, "active": true, "ref": "00421"}
JSON
# class User < FieldStruct::Base
#   required :name, :string
#   required :age, :integer
#   required :active, :boolean
#   required :ref, :string # numeric-looking (e.g. "00421") — :integer? or keep :string if an id/code
# end
```

It's deliberately conservative: JSON objects become nested classes (emitted before their parent), arrays become `:array, of: …`, real JSON booleans/numbers map to `:boolean`/`:integer`/`:float`, and **strings stay `:string`** — including numeric-looking ones, because an `authorization_code` must not silently become an Integer. The guesses are surfaced as trailing comments, not committed types.

Pass an **array of same-shape objects** to gather more signal: empty fields get resolved from samples that have them, presence across samples drives `required` vs `optional`, and small repeated vocabularies surface as `# values: [...] — enum?` hints.

```ruby
FieldStruct::Scaffold.from_json('[{"kind":"cc"},{"kind":"ach"},{"kind":"cc"}]')
# … optional :kind, :string # values: ["cc", "ach"] — enum?
```

For the full scaffold-then-refine workflow (and how it fits a Rails integration), see [`docs/getting_started.md`](docs/getting_started.md).

## Claude Code skill

The gem bundles a [Claude Code](https://claude.com/claude-code) skill (`skills/field-struct/SKILL.md`) that teaches the assistant the DSL, the common mistakes, and how to debug an invalid instance — so editing FieldStruct models in a dependent project goes correctly.

**Install as a plugin** (recommended — the repo doubles as a single-plugin marketplace):

```text
/plugin marketplace add Paymentbox-com/field_struct
/plugin install field-struct@field-struct
```

**Or copy it into your project** (no marketplace needed) — the skill ships in the gem package:

```bash
mkdir -p .claude/skills/field-struct
cp "$(bundle show field_struct)/skills/field-struct/SKILL.md" .claude/skills/field-struct/
```

Either way it triggers when you ask Claude to define, edit, or debug a `FieldStruct::Base` subclass. The skill points at [`USAGE.md`](USAGE.md) (also shipped) for the exhaustive reference.

## Performance

Indicative numbers from `bundle exec rake bench` (`benchmarks/run.rb`, no dependencies; `BENCH_SECONDS=n` sets the time per case). Ruby 4.0.7 on an Apple M4, FieldStruct 0.13.0. Mean time per call. Inputs are already the right types, except that `from_json` parses a string:

| case | µs/call | calls/sec |
|---|---:|---:|
| `new` (5 fields) | 8.1 | 124,000 |
| `new` (5 fields, `strict: true`) | 8.2 | 122,000 |
| `from_json` (5 fields) | 10.4 | 96,000 |
| `to_json` (5 fields) | 2.3 | 445,000 |
| `new` (nested struct) | 9.4 | 106,000 |
| `new` (array of 100 integers) | 13.3 | 75,000 |
| `new` (validation-heavy: `email`, `enum:`, `in:`, `format:`, 2 dates, a `validate` block) | 18.7 | 53,000 |

`strict: true` costs nothing measurable. Every assignment runs coercion and validation, so the cost scales with the number of fields assigned rather than with the size of the class. Numbers vary with CPU and Ruby version. Compare runs on one machine.

## Development

```bash
bundle install
bin/rspec                          # run specs
COVERAGE=1 bin/rspec               # run specs with SimpleCov
bundle exec rubocop                # lint
bundle exec rake                   # all of the above
bundle exec rake bench             # indicative benchmarks (not part of the default task)
```

The plan-of-record for Phase 1 lives in [`docs/origin/plan.md`](docs/origin/plan.md).

## Contributing

Bug reports and pull requests are welcome at <https://github.com/Paymentbox-com/field_struct>. Contributors are expected to follow the [code of conduct](CODE_OF_CONDUCT.md).

## License

[MIT](LICENSE.txt).
