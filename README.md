# `site` branch: docs for field_struct and actionable

This orphan branch holds the public documentation site for two Ruby gems,
[field_struct](https://github.com/Paymentbox-com/field_struct) and
[actionable](https://github.com/Paymentbox-com/actionable). It shares no history
with the gem's code branches.

- Generator: [Starlight](https://starlight.astro.build) on Astro (`astro` 7.4.2, `@astrojs/starlight` 0.42.7, pinned exactly in `package.json`).
- Published at <https://aemadrid-twx.github.io/field_struct/> by GitHub Actions, from the `site` branch of the [aemadrid-twx/field_struct](https://github.com/aemadrid-twx/field_struct) fork, where development happens. Releases, and the install lines and links on the site, stay on Paymentbox-com.
- Pages live in `src/content/docs/`, grouped Diátaxis-style: `tutorial/`, `how-to/`, `reference/`, `explanation/`.

## Run it locally

Needs Node 22.23+ (CI uses 24) and Ruby 3.2+ (CI uses 3.4).

```sh
npm ci
npm run dev          # http://localhost:4321/field_struct/
npm run build        # static site into dist/
bundle install
npm run check:code   # same as: bundle exec ruby bin/check-code-blocks
```

## Runnable code blocks

Docs must never go stale, so code examples are executed in CI against the
**released** gems pinned in `Gemfile` (field_struct `v0.15.0`, actionable
`v1.9.0`, installed from their git tags). When a gem ships a new release, bump
the tag in `Gemfile`, run `bundle lock`, and fix whatever the checker reports.

Mark a block runnable by adding the word `run` to its fence:

````md
```ruby run
book = Book.new(title: 'Eloquent Ruby', price: '24.99')
book.price   # => BigDecimal('24.99')
```

```ruby title="book.rb" run
class Book < FieldStruct::Base
  ...
end
```
````

Plain ` ```ruby ` blocks (Gemfile snippets, fragments) are shown but not run.

How the checker (`bin/check-code-blocks`) runs them:

- All runnable blocks of one page run **in order, in one fresh Ruby process**,
  sharing classes, constants and local variables, so a tutorial can build up step
  by step. Pages don't see each other.
- `field_struct` and `actionable` are already required.
- A line `expr # => expected` is an assertion: both sides are evaluated as Ruby
  and compared with `==` (so `{ a: 1 }` and `{a: 1}` both match). Keep the
  expression on one line. If `expected` isn't valid Ruby, such as `#<Book ...>`
  inspect output, the line still runs but isn't asserted.
- Any exception, or a failed assertion, fails the check with the file and line.
  The checker also fails if it finds no runnable blocks at all.

This borrows the approach of field_struct's own `spec/docs_examples_spec.rb`
(`<!-- doctest -->` blocks in README/USAGE), changed to per-page shared state.

A failure looks like:

```text
FAIL src/content/docs/tutorial/bookstore-checkout.md:34
    book.title
    documented: # => "Eloquent Rubyy"  ("Eloquent Rubyy")
    actual:                "Eloquent Ruby"
```

## Deploy

`.github/workflows/site.yml` runs on push and pull request to `site`:
`npm ci`, `astro build`, then the code-block checker. On a push to `site` (or a
manual `workflow_dispatch`) a second job deploys `dist/` to GitHub Pages with
`actions/upload-pages-artifact` and `actions/deploy-pages`. Pull requests build
and check but never deploy.

### One-time repository setup (an admin does this once)

1. **Settings → Pages → Build and deployment → Source: GitHub Actions.**
2. If the `github-pages` environment restricts which branches may deploy
   (Settings → Environments → github-pages → Deployment branches and tags), add `site`.

Until then the deploy job fails; the build and check job is unaffected.
