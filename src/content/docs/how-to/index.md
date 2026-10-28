---
title: How-to guides
description: Short recipes for specific tasks with FieldStruct and Actionable.
sidebar:
  label: Overview
  order: 1
---

Each guide solves one task in a few steps. They assume you know the basics. If
you don't yet, start with the [tutorial](../tutorial/bookstore-checkout/).
Every runnable example is checked in CI against field_struct v0.16.0 and
actionable v1.10.0.

## Structs (field_struct)

- [Validate request params](validate-request-params/): coerce a params Hash, reject unknown keys, return errors as JSON.
- [Use camelCase JSON keys](camelcase-json/): keep snake_case in Ruby, read and write the API's names.
- [Keep secrets out of logs](hide-sensitive-values/): mask card numbers and tokens in `inspect`, filter them from JSON.
- [Dates, times and zones](dates-and-time-zones/): accept a date format, require offsets, pin a local zone.
- [Nested structs and arrays](nested-structs-and-arrays/): find which element of a list is invalid.

## Actions (actionable)

- [Declare and handle outcomes](handle-action-outcomes/): name the ways an action fails or skips, branch on them.
- [Compose actions](compose-actions/): call one action from another as a step.
- [Run in a background job](background-jobs/): retry or discard a job based on the failure code.
- [Use ActiveRecord transactions](activerecord-transactions/): roll back on failure, send email after the commit.
- [Test with RSpec](test-with-rspec/): assert outcomes, stub collaborator actions.
- [Generate RBS signatures](generate-rbs/): types for your structs and actions.
- [Lint with the RuboCop cop](catch-misplaced-verbs/): catch a `fail` that doesn't stop the run.

Looking for every option? The [field_struct USAGE](https://github.com/aemadrid-twx/field_struct/blob/v0.16.0/USAGE.md)
and [actionable USAGE](https://github.com/aemadrid-twx/actionable/blob/v1.10.0/USAGE.md)
references list them all.
