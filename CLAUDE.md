# Hologram

## Test apps and the Hologram dep ref

The test apps under `test/` that depend on Hologram through a git dep (the `git:` entry in their `mix.exs`) build from the commit their ref points at, not from the working tree.

- The library is the code the git dep builds from (`lib/`, `assets/` and the like). Changes to tests, test apps, docs, llms files, CI or config don't count.
- Bump a test app's ref only when the library changed since the commit the ref points at. A feature test commit never makes another bump needed.
- Before implementing feature tests, bump the ref in all feature test apps to the last commit that changed the library, then compile the feature test app. Skip the bump when the refs already point there, for example on a second feature test commit with no library change in between.
- A branch that changes the library ends with a commit that bumps the refs in all test apps to the last commit that changed the library, even when it has no feature tests. That commit skips any test app whose ref already points there. A branch that changes only CI, config or the test apps themselves gets no bump commit.
- After any bump, run `mix deps.get` in each bumped test app, then delete the formatter caches by running `find test/*/_build -name cached_dot_formatter -delete` from the repo root. If a format check still asks for parentheses on `attribute`, `allow`, `relationship`, `role` or `policy`, the test app's Hologram copy is stale. Never fix it by formatting the files.

## Running tests

Run only the tests that cover what changed, never a whole suite. CI runs the rest.

- Elixir unit tests: pass the test files, or `file:line` for single tests, to `mix test`.
- JavaScript unit tests: pass the test file to `mix test.js`, for example `mix test.js test/javascript/client_test.mjs`. It takes one file and ignores the rest, so run it once per file.
- Feature tests: run only the feature tests that cover what changed.
- Don't use `mix t`, it runs the full Elixir and JavaScript suites.

## Checks for changed code

Run these for each project a change touches: the library from the repo root, a test app from its own folder. CI runs the full checks.

- Compile: `mix compile --all-warnings --warnings-as-errors`.
- Elixir format: `mix format <files>`.
- JavaScript format: `mix format.js`, in the library and the features app. It formats the whole tree, which takes a few seconds.
- Elixir lint: `mix credo --strict <files>`.
- JavaScript lint: `mix eslint`, from the repo root. It lints the whole tree, which takes a few seconds.
- Dialyzer: `mix dialyzer`, when the change touches the project's Elixir code. It always checks the whole project.
- New Elixir test files: `mix holo.check.test_file_names test/elixir` in the library, `mix holo.check.test_file_names test` in a test app.

## Bug fixes

New tests for a bug fix must fail without the fix, and fail because of the bug, not a compile error.

- Unit tests: undo the fix by hand, run only the new unit tests, then put the fix back.
- Feature tests: run only the new feature tests, once on the fix and once with the Hologram dep pinned to the pre-fix commit, then restore the pin.

## Docs

Docs for a change live in two repos:

- Hologram repo: update `llms-full.txt`, `llms.txt` and `usage-rules.md`.
- Hologram website repo (`/Users/bartblast/Projects/hologram_website`): update the related docs pages, and carry the `llms-full.txt` and `llms.txt` changes over to `priv/static/llms-full.txt` and `priv/static/llms.txt` edit for edit, without rewording anything. Don't use `mix sync_llms_txts`, it syncs the whole files, not just your changes.
