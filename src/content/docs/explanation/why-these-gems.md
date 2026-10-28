---
title: Why these gems
description: The experience behind field_struct and actionable, in the first person - what the 2016 originals taught, and what the rebuild set out to fix.
sidebar:
  order: 8
---

I wrote the first versions of both gems in 2016, by hand, for Rails apps that
needed two things over and over: a typed bag of data, and a service object
that could say plainly how it ended. They did the job for a long time. They
also taught me where they hurt.

## What the originals taught me

The original field_struct was, in its own README's words, heavily based on
ActiveModel. That made it feel at home in Rails, and it also meant it could
never behave the same outside of it. I still like the shape. I'm coming from a
Rails world, and `valid?`, `errors` and `attributes` are the methods my hands
reach for. So the rebuild keeps the shape and drops the dependency.

The original actionable short-circuited with exceptions and a bare
`rescue Exception`, which swallowed real errors along with the ones it meant
to catch. A failure that might be a crash is not information. Today a
`Failure` always means the action decided to fail, and a crash stays a crash.

It also surfaced every instance variable a run set. Convenient, but nobody
could tell from the class what an action returned. I'm not saying a step
shouldn't set what it needs. I'm saying what leaves the action should be
declared, typed and checked.

And the README rotted. Typos and behaviour drift sat in a document no test
ever read. That is why every runnable example on this site runs in CI against
the released gems.

## What the rebuild is for

The rebuild in 2026 was done with AI agents, and on purpose it is stricter
than the original, not looser:

- outcomes are honest - success, failure or skip, and a skip is information,
  not a fake success
- types are checked at the boundary, and an invalid object looks invalid the
  moment you print it
- mistakes surface when the class is defined, not in production
- observability is built in, as it has been since 2016, through the run
  history
- the gems explain themselves, to humans and to agents, through `describe`,
  USAGE and a skill file shipped with the code

Some of this costs a little ceremony up front, like declaring an output or a
failure code. I would rather pay that once in the class than many times while
debugging.

## Small on purpose

Both gems are deliberately narrower than what inspired them. field_struct is
not a database layer, not a form object and not an ActiveModel replacement.
actionable keeps its core pure Ruby and puts Rails behind an explicit require.
For now that is the right size, and I would love for other people's needs to
push on it. That is also why the rest of these docs say "we".

## Related

- [ActiveModel-shaped, framework-free](../framework-independence/)
- [Success, failure, skip](../three-outcomes/)
- [first discussion (actionable)](https://github.com/aemadrid-twx/actionable/blob/v1.10.0/docs/origin/first_discussion.md)
  and [first discussion (field_struct)](https://github.com/aemadrid-twx/field_struct/blob/v0.16.0/docs/origin/first_discussion.md)
