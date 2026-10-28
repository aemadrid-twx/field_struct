---
title: Instance API
description: Building, reading, updating, copying, comparing and pattern-matching FieldStruct instances.
sidebar:
  order: 6
---

Everything you can call on an instance (and the class methods that build one).
The method names follow ActiveModel's where they overlap, but FieldStruct
reuses none of its code.

| Method | Returns |
|---|---|
| `Klass.new(hash = {})` | a new instance; defaults, then each key through its setter, then cross-field validators |
| `Klass.from_json(string)` | a new instance from JSON; see [JSON and serialization](../json-and-serialization/) |
| `record.field` / `record.field = value` | the value / the coerced value |
| `attributes` / `to_h` | `{field => value}` in declaration order |
| `attribute_names` | declared field names (also on the class) |
| `assign_attributes(hash)` | `self`, after running each key through its setter |
| `with(**changes)` | a new instance with those fields changed |
| `valid?` / `invalid?` | whether `errors` is empty, after rerunning cross-field validators |
| `errors` | a `FieldStruct::Errors`; see [Validation and errors](../validation-and-errors/#the-errors-object) |
| `as_json` / `to_json` | JSON-ready Hash / JSON String |
| `==` / `eql?` / `hash` | structural equality |
| `inspect` | `#<Klass field: value, …>`, plus `errors: {…}` when invalid |
| `deconstruct_keys` / `deconstruct` | pattern-matching support |
| `model_name` / `to_model` | ActiveModel-shaped naming / `self` |

## `new`

Takes a Hash with Symbol or String keys, or anything that responds to `to_hash`
(a permitted `ActionController::Parameters`, for example). `new(nil)` is the
same as `new`. Any other argument raises `ArgumentError`.

```ruby run
class User < FieldStruct::Base
  required :name, :string
  optional :age,  :integer
end

User.new('name' => 'Alice', age: '30').attributes # => { name: "Alice", age: 30 }
User.new(nil).errors.to_h                          # => { name: ["is required"] }

err = begin
  User.new([])
rescue ArgumentError => e
  e
end
err.message # => "User.new expects a Hash (or an object responding to #to_hash), got Array"
```

`new` applies defaults first, then assigns the given keys, then runs any
`validate` blocks, then (for `frozen!` classes) freezes the object. Unknown keys
follow [`unknown_attributes`](../class-macros/#unknown_attributes).

## Readers and setters

Each field gets a reader that returns the stored value and a setter that runs
the [pipeline](../validation-and-errors/#the-setter-pipeline) and returns the
coerced value. Setters are permissive on purpose: `user.age = '31'` works.

```ruby run
u = User.new(name: 'Alice')
u.age = '31'
u.age            # => 31
u.attribute_names # => [:name, :age]
User.attribute_names # => [:name, :age]
```

## `attributes` / `to_h`

A new Hash of every field, in declaration order, under canonical names. Nested
structs stay as objects (use `as_json` for plain data). `description:` and
`serialize` mappings never show up here.

```ruby run
u.to_h == u.attributes # => true
u.to_h                 # => { name: "Alice", age: 31 }
```

## `assign_attributes`

Bulk update through the setters. Takes the same input as `new`, except that
`nil` raises. Returns `self`.

```ruby run
u.assign_attributes(age: 40).equal?(u) # => true
u.age                                   # => 40
```

## `with`

Returns a new instance of the same class with the given fields changed, like
`Data#with`. The receiver is never modified, so this is how you "change" an
`immutable!` or `frozen!` instance.

- Changed fields go through the setter pipeline (coercion, the coercion policy,
  that field's errors rewritten). Under `:raise` the `CoercionError` propagates
  and no copy is returned. Cross-field validators rerun.
- Unchanged fields are copied as they are, errors included. Callable defaults
  are not called again.
- It is shallow: an unchanged nested struct or array is the same object in both.
- Keywords only (`with(**hash)` for a Hash). String keys work. Unknown keys
  follow `unknown_attributes`.
- `with` with no changes returns an equal copy, not `self`.
- The copy is immutable when the class is, and frozen when the receiver is.

```ruby run
class Point < FieldStruct::Base
  immutable!
  required :x, :integer
  required :y, :integer
end

origin = Point.new(x: 0, y: 0)
moved  = origin.with(x: '5')
moved.x                     # => 5
origin.x                    # => 0
origin.with('y' => 2).y     # => 2
origin.with(y: nil).valid?  # => false
origin.with == origin       # => true
origin.with.equal?(origin)  # => false

err = begin
  origin.with({ x: 1 })
rescue ArgumentError => e
  e
end
err.message # => "Point#with takes keyword arguments only, got 1 positional; pass a Hash as with(**hash)"
```

## `dup` / `clone`

Ruby's usual copies, plus the errors: the copy starts with the original's
messages but owns them, so fixing a field on one doesn't change the other's
`valid?`. Nested structs are shared.

```ruby run
broken = User.new
copy   = broken.dup
copy.name = 'Bob'
copy.valid?   # => true
broken.valid? # => false
```

## Equality

`==` (and `eql?`) is true for two instances of exactly the same class with
equal `attributes`. Errors are ignored, and a subclass instance never equals a
parent instance. `hash` is `[self.class, attributes].hash`, so instances work as
Hash keys and in Sets.

```ruby run
class Admin < User; end

User.new(name: 'A') == User.new(name: 'A')        # => true
User.new(name: 'A').hash == User.new(name: 'A').hash # => true
User.new(name: 'A') == Admin.new(name: 'A')       # => false
User.new(age: 'x') == User.new(age: 'x')          # => true
```

## `inspect`

Shows every field. An invalid instance appends its errors, so it never looks
fine when it is not. `sensitive: true` fields show `[FILTERED]`. An anonymous
class shows as `AnonymousFieldStruct`.

```ruby run
User.new(name: 'Alice', age: 30).inspect # => '#<User name: "Alice", age: 30>'
User.new(age: 30).inspect                # => '#<User name: nil, age: 30 errors: {name: ["is required"]}>'
```

`FieldStruct.use_alias!(:FS)` shortens the `FieldStruct::` prefix in the
`inspect` of `Field`, `Metadata`, `Errors`, `Registry` and type objects. See
[Registries and custom types](../registries-and-custom-types/#use_alias).

## Pattern matching

Hash patterns match declared fields by canonical name. Array patterns bind
values in declaration order. Nested structs recurse. Errors are not part of
either, and `serialize` names don't apply.

```ruby run
alice = User.new(name: 'Alice', age: 30)

case alice
in { name: 'Alice', age: Integer => age }
  age # => 30
end

case alice
in [name, age]
  name # => "Alice"
end

alice.deconstruct_keys([:name]) # => { name: "Alice" }
alice.deconstruct_keys(nil)     # => { name: "Alice", age: 30 }
alice.deconstruct               # => ["Alice", 30]
```

## `model_name` / `to_model`

`model_name` (on the class and the instance) returns a `FieldStruct::ModelName`
with `name`, `singular`, `plural` and `element`. `to_s` / `to_str` return
`name`. `to_model` returns `self`. Persistence methods (`to_key`, `to_param`,
`persisted?`) are not provided.

`plural` is `element` with an `s` appended. There is no inflector.

```ruby run
class LineAddress < FieldStruct::Base; end

name = LineAddress.model_name
name.name      # => "LineAddress"
name.element   # => "line_address"
name.singular  # => "line_address"
name.plural    # => "line_addresss"
LineAddress.new.to_model.class # => LineAddress
```

Upstream: [USAGE, Instance surface](https://github.com/aemadrid-twx/field_struct/blob/v0.16.0/USAGE.md#instance-surface).
