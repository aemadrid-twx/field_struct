---
title: Explanation
description: The ideas behind the design of field_struct and actionable.
sidebar:
  label: Overview
  order: 1
---

These pages explain *why* the two gems behave the way they do. They don't teach
you the API (that is the [tutorial](../tutorial/bookstore-checkout/)) and they
don't list every option (that is the [reference](../reference/)). Read them
when a behaviour surprises you, or before you argue with it.

Each page is grounded in the gems' own design records, which keep the reasoning
behind every locked decision:

- field_struct: [`docs/origin/plan.md`](https://github.com/aemadrid-twx/field_struct/blob/v0.16.0/docs/origin/plan.md)
  (decisions D1–D15, plus the Phase 2 decisions such as N3 and S1) and the
  [project intent](https://github.com/aemadrid-twx/field_struct/blob/v0.16.0/.claude/project_intent.md)
  (its design invariants).
- actionable: [`docs/origin/plan.md`](https://github.com/aemadrid-twx/actionable/blob/v1.10.0/docs/origin/plan.md)
  (decisions D1–D23) and the
  [project intent](https://github.com/aemadrid-twx/actionable/blob/v1.10.0/.claude/project_intent.md).

When a page cites "D17" or "invariant 3", that is where to look. When the
records describe a behaviour without saying why, these pages say so. We would
rather admit a gap than guess.

## The pages

**field_struct**

- [Validity is computed on assignment](validity-on-assignment/): every setter
  checks its own field, `valid?` is a read, and an invalid object never *looks*
  fine.
- [Coercion vs. validation](coercion-and-validation/): turning input into a
  type and judging the typed value are two steps, with two kinds of error.
- [ActiveModel-shaped, framework-free](framework-independence/): why the
  methods look like Rails, but the code doesn't depend on it and behaves the
  same with or without ActiveSupport.

**actionable**

- [Success, failure, skip](three-outcomes/): why a run has three outcomes, and
  why halting uses `throw` instead of exceptions.
- [Declared failures and result codes](declared-outcomes/): listing on the
  class every way an action can end.

**Both**

- [How the two gems fit together](how-the-gems-fit/): actionable hands all
  typing and validation to field_struct.
