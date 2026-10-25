---
title: How to handle dates, times and time zones
description: Accept dates in a given format, require an offset on API timestamps, and pin a zone for local wall-clock times.
sidebar:
  label: Dates, times and zones
  order: 5
---

Three field types hold time: `:date`, `:time` and `:datetime`. Declare a
`format:` for the strings you accept, and a `zone:` when a string carries no
offset.

## Accept a specific date format

Give `format:` a strftime string, or a preset (`:iso8601`, `:us`, `:eu` for
dates). `as_json` writes the same format back, so JSON round-trips:

```ruby title="booking.rb" run
class Booking < FieldStruct::Base
  required :check_in,  :date, format: '%m/%d/%Y'
  optional :check_out, :date, format: :us, in: (Date.new(2026, 1, 1)..)
end

booking = Booking.new(check_in: '10/24/2026', check_out: '10/27/2026')
booking.check_in             # => Date.new(2026, 10, 24)
booking.as_json[:check_in]   # => "10/24/2026"
```

A string in another shape, or a day that doesn't exist, is refused. `in:`
works on dates like on numbers:

```ruby run
Booking.new(check_in: '2026-10-24').errors[:check_in]  # => ['could not be coerced: does not match format "%m/%d/%Y"']
Booking.new(check_in: '02/30/2026').valid?             # => false
Booking.new(check_in: '10/24/2026', check_out: '12/31/2025').errors[:check_out]  # => ["is invalid"]
```

## Require an offset on API timestamps

`format: :iso8601` means RFC 3339: a full date and time with a mandatory offset
(`Z` or `±hh:mm`). A timestamp without one is refused instead of guessed:

```ruby run
class Event < FieldStruct::Base
  required :occurred_at, :time, format: :iso8601
end

Event.new(occurred_at: '2026-10-24T10:00:00Z').occurred_at.utc_offset      # => 0
Event.new(occurred_at: '2026-10-24T10:00:00+02:00').occurred_at.utc_offset  # => 7200
Event.new(occurred_at: '2026-10-24T10:00:00').errors[:occurred_at]       # => ["could not be coerced: expected an RFC 3339 timestamp"]
```

## Pin the zone of a local time

Without `zone:`, a `:time` string with no offset lands in the server's own zone,
so the same input means different instants on different servers. Name the zone
it means instead. An IANA name follows daylight saving time:

```ruby run
class Shift < FieldStruct::Base
  required :starts_at, :time, zone: 'America/Denver'
end

Shift.new(starts_at: '2026-07-15 09:00').starts_at.utc_offset  # => -6 * 3600
Shift.new(starts_at: '2026-01-15 09:00').starts_at.utc_offset  # => -7 * 3600
Shift.new(starts_at: '2026-01-15T09:00:00Z').starts_at.utc_offset  # => 0
```

`zone:` only fills in a missing offset; a string that carries one keeps it. A
local time that doesn't exist (inside the spring-forward hour) is refused:

```ruby run
Shift.new(starts_at: '2026-03-08 02:30').errors[:starts_at]  # => ["could not be coerced: names a local time that does not exist in America/Denver (skipped by a daylight-saving change)"]
```

`zone:` also takes `'UTC'` and fixed offsets like `'-06:00'`. Rails zone names
like `'Mountain Time (US & Canada)'` are refused when the class loads; use the
IANA name.

## See also

- field_struct USAGE: [The temporal contract](https://github.com/Paymentbox-com/field_struct/blob/v0.16.0/USAGE.md#the-temporal-contract), [Zones](https://github.com/Paymentbox-com/field_struct/blob/v0.16.0/USAGE.md#zones-zone)
