---
title: Dates, times and zones
description: The :date, :time and :datetime types — parsing rules, format presets, RFC 3339, and the zone option.
sidebar:
  order: 3
---

Three temporal types. Each takes `format:` and `in:`; `:time` and `:datetime`
also take `zone:`.

| Type | Holds | Coerces from |
|---|---|---|
| `:date` | `Date` | String; `Date`; `DateTime` / `Time` narrowed to their calendar day |
| `:time` | `Time` | String; `Time`; `DateTime` (same instant and offset); `Date` (midnight) |
| `:datetime` | `DateTime` | String; `DateTime`; `Time` (same instant and offset); `Date` (midnight) |

Anything else (an Integer epoch, say) is a coercion failure:
`expected a String, Date, DateTime or Time, got Integer`. Conversions between
classes are built from components, so they behave the same with or without
ActiveSupport loaded.

```ruby run
class Stamp < FieldStruct::Base
  optional :on, :date
  optional :at, :time
end

Stamp.new(on: '2026-07-03').on                             # => Date.new(2026, 7, 3)
Stamp.new(on: Time.new(2026, 7, 3, 23, 0, 0, '+00:00')).on # => Date.new(2026, 7, 3)
Stamp.new(at: 5).errors[:at] # => ["could not be coerced: expected a String, Date, DateTime or Time, got Integer"]
```

## Parsing strings

Three rules hold for all three types:

- **A declared `format:` anchors.** Trailing characters are refused rather than
  dropped. That's all "anchors" means: a hand-written format stays
  strptime-lenient about widths and signs.
- **A day that never existed is refused.** `'2026-06-31'` is not 1 July.
- **With no `format:`, the string must name a whole day** (year, month and
  day). `'10:30'` or `'July'` would depend on when it was parsed. A declared
  partial format (`format: '%H:%M'`) still works.

A blank string is a coercion failure, not "missing".

```ruby run
class Window < FieldStruct::Base
  optional :on,    :date
  optional :exact, :date, format: '%Y-%m-%d'
  optional :at,    :time
end

Window.new(on: '2026-06-31').errors[:on]       # => ["could not be coerced: invalid date"]
Window.new(on: 'July').errors[:on]             # => ["could not be coerced: expected a date with a year, a month and a day"]
Window.new(at: '10:30').errors[:at]            # => ["could not be coerced: expected a date with a year, a month and a day"]
Window.new(exact: '2026-07-031').errors[:exact] # => ["could not be coerced: does not match format \"%Y-%m-%d\" — unexpected trailing characters"]
Window.new(at: '').errors[:at]                 # => ["could not be coerced: expected a date with a year, a month and a day"]
```

Without `format:`, `:date` reads through `Date.parse`, `:time` through
`Time.parse` and `:datetime` through `DateTime.parse` (after the checks above).
With a strftime `format:`, they use `strptime`.

## `format:`

A strftime String, or a preset Symbol. The format is used both ways: to parse
input strings and to render `as_json` / `to_json`. With no format, output is
ISO 8601 (`value.iso8601`).

| Preset | `:date` | `:time` / `:datetime` |
|---|---|---|
| `:iso8601` | RFC 3339 full date (`2026-07-03`) | RFC 3339 timestamp (`2026-07-03T10:30:00Z`) |
| `:us` | `'%m/%d/%Y'` | — |
| `:eu` | `'%d/%m/%Y'` | — |
| `:rfc2822` | — | `'%a, %d %b %Y %H:%M:%S %z'` |
| `:db` | — | `'%Y-%m-%d %H:%M:%S'` |

An unknown preset raises at declaration: `unknown time format preset :us.
Available: [:iso8601, :rfc2822, :db]`.

```ruby run
class Shipment < FieldStruct::Base
  optional :ship_by, :date, format: :us
  optional :placed,  :time, format: :db, zone: 'UTC'
  optional :joined,  :date, format: '%d.%m.%Y'
end

s = Shipment.new(ship_by: '07/03/2026', placed: '2026-07-03 10:00:00', joined: '03.07.2026')
s.ship_by                 # => Date.new(2026, 7, 3)
s.as_json[:ship_by]       # => "07/03/2026"
s.as_json[:placed]        # => "2026-07-03 10:00:00"
s.as_json[:joined]        # => "03.07.2026"
```

### `format: :iso8601` is RFC 3339

FieldStruct parses and renders this preset itself, rather than through
`Time.iso8601` / `DateTime.iso8601` (which disagree with each other) or a
strftime string.

- **Date:** exactly `YYYY-MM-DD`, and a real day.
- **Timestamp:** `YYYY-MM-DD`, `T` (or `t`), `hh:mm:ss`, an optional fraction
  of a second, and a **mandatory** offset: `Z` (or `z`), `±hh:mm`, or `±hhmm`
  (accepted for input because FieldStruct 0.9.0 emitted it).
- Refused: `2026-7-3`, `+2026-07-03`, `20260703`, week and ordinal dates, a
  missing offset, hour 24, second 60, an offset hour above 23.
- Output: `Z` for UTC, `+HH:MM` otherwise, and the fraction's exact digits
  (none when it's a whole second).

```ruby run
class Api < FieldStruct::Base
  optional :on, :date,     format: :iso8601
  optional :at, :time,     format: :iso8601
  optional :dt, :datetime, format: :iso8601
end

Api.new(at: '2026-07-03T10:30:00.25+02:00').as_json[:at] # => "2026-07-03T10:30:00.25+02:00"
Api.new(at: '2026-07-03T10:30:00Z').as_json[:at]         # => "2026-07-03T10:30:00Z"
Api.new(at: '2026-07-03T10:30:00+0200').at.utc_offset    # => 7200
Api.new(on: '2026-7-3').errors[:on]                       # => ["could not be coerced: expected an RFC 3339 date"]
Api.new(dt: '2026-07-03T10:30:00').errors[:dt]            # => ["could not be coerced: expected an RFC 3339 timestamp"]
Api.new(at: '2026-07-03T24:00:00Z').errors[:at]           # => ["could not be coerced: invalid time of day"]
Api.new(at: '2026-02-30T10:00:00Z').errors[:at]           # => ["could not be coerced: invalid date"]
```

`zone:` has no effect on string input with `format: :iso8601`, which always carries an offset; a `Date` still becomes midnight in that zone.

## `in:`

An Array (membership) or a Range (`cover?`, so endless and beginless ranges
work, and a date range compares endpoints rather than enumerating days).

```ruby run
class Booking < FieldStruct::Base
  optional :on, :date, in: Date.new(2024, 1, 1)..Date.new(2024, 12, 31)
end

Booking.new(on: '2024-06-01').valid?     # => true
Booking.new(on: '2025-01-01').errors.to_h # => { on: ["is invalid"] }
```

## `zone:`

Without `zone:`, a string with no offset follows the stdlib: `:time` uses
`Time.parse` and lands in the **process** time zone, `:datetime` uses
`DateTime.parse` and lands in **UTC**. So the same `:time` input is a different
instant on servers in different zones.

`zone:` names the zone a zone-less value means. It only fills in a **missing**
offset; it never changes one the input carries.

| `zone:` value | Meaning |
|---|---|
| `"UTC"` | UTC (a `:time` value is then `utc?`) |
| `"+HH:MM"` / `"-HH:MM"` | a fixed offset, `-23:59` to `+23:59`, colon required |
| an IANA name (`"America/Denver"`, `"Etc/UTC"`) | the offset in force at that date, following daylight saving |

Refused at declaration with an `ArgumentError` naming the option: `"utc"`, `"Z"`,
`"-0600"`, abbreviations and aliases without a `/` (`"MST"`), unknown names, and
Rails zone names (`"Mountain Time (US & Canada)"`), which exist only when
ActiveSupport is loaded. `zone:` doesn't apply to `:date`.

| Input | no `zone:` | `zone: "-06:00"` | `zone: "America/Denver"` |
|---|---|---|---|
| `"2026-10-22 10:00"` | `:time` process zone; `:datetime` UTC | 10:00 at -06:00 | 10:00 at that day's Denver offset |
| a `format:` without `%z` | as above | at -06:00; a date the format omits is today in -06:00 | at that date's offset; an omitted date is today in Denver |
| a string with an offset (`+02:00`, `Z`, `EST`) | its own offset | its own offset | its own offset |
| a string naming a zone with no fixed offset (`XYZ`, `America/Denver`) | `:time` process zone; `:datetime` UTC | refused | refused |
| `Time` / `DateTime` | kept | kept (not converted) | kept (not converted) |
| `Date` | midnight: `:time` process zone, `:datetime` UTC | midnight at -06:00 | midnight at that day's offset |
| Integer | refused | refused | refused |

```ruby run
class Shift < FieldStruct::Base
  required :starts, :time,     zone: '-06:00'
  optional :logged, :datetime, zone: 'UTC'
  optional :local,  :time,     zone: 'America/Denver'
end

Shift.new(starts: '2026-10-22 10:00').starts.utc_offset                 # => -21600
Shift.new(starts: '2026-10-22T10:00:00+02:00').starts.utc_offset        # => 7200
Shift.new(starts: Date.new(2026, 1, 2)).starts                          # => Time.new(2026, 1, 2, 0, 0, 0, '-06:00')
Shift.new(starts: '2026-10-22 10:00', logged: '2026-10-22 10:00').logged.offset # => 0
Shift.new(starts: '2026-07-01 10:00', local: '2026-07-01 10:00').local.utc_offset # => -21600
Shift.new(starts: '2026-01-15 10:00', local: '2026-01-15 10:00').local.utc_offset # => -25200
Shift.new(starts: '2026-10-22 10:00 XYZ').errors[:starts] # => ["could not be coerced: names a time zone with no fixed offset, which zone: does not override"]
```

### Daylight-saving edges (IANA names only)

- A wall-clock time the zone **skips** is refused.
- A wall-clock time the zone **repeats** is read at the daylight-time offset,
  the earlier instant (what ActiveSupport's `TimeWithZone` picks).
- A `Date` whose midnight the zone skips becomes the first moment of that day.

```ruby run
Shift.new(starts: '2026-11-01 10:00', local: '2026-11-01 01:30').local.utc_offset # => -21600
Shift.new(starts: '2026-03-08 10:00', local: '2026-03-08 02:30').errors[:local] # => ["could not be coerced: names a local time that does not exist in America/Denver (skipped by a daylight-saving change)"]
```

### What you get back

A plain `Time` (or `DateTime`) with that offset. It doesn't remember the zone:
adding a day keeps the offset rather than following DST. Reassign to re-read.

The zone database is [tzinfo](https://github.com/tzinfo/tzinfo)'s, loaded only
when a field declares an IANA name. On a system without zoneinfo (Windows, slim
containers) such a declaration raises `ArgumentError` asking you to add the
`tzinfo-data` gem.

Upstream: [USAGE, The temporal contract](https://github.com/aemadrid-twx/field_struct/blob/v0.16.0/USAGE.md#the-temporal-contract) and [Zones](https://github.com/aemadrid-twx/field_struct/blob/v0.16.0/USAGE.md#zones-zone).
