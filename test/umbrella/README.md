# Hologram Umbrella Tests

End-to-end tests for Hologram in an umbrella project layout.

App structure:

- `apps/app_1` - Phoenix + Hologram endpoint app serving all pages
- `apps/app_2` - plain library app called from `app_1`'s pages (no Hologram dep)
- `apps/app_3` - pages-library app (Hologram dep, no `:hologram` compiler entry) whose pages are served through `app_1`'s endpoint

## Running the tests

```
mix deps.get
mix test
```

## Manual live reload check

Live reload can't be reliably automated (it requires editing source files while the server runs), so verify it manually:

```
mix deps.get
mix holo
```

Open http://localhost:4000, then edit the message returned by `apps/app_2/lib/app_2.ex` - the browser should reload automatically and show the new value.
