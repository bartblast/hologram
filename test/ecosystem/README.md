# Hologram Ecosystem Tests

End-to-end tests for Hologram used together with libraries of the Elixir ecosystem.

The app's pages put ecosystem structs (an `ash_money` `%Money{}`, Ecto schemas) into the state or drop them on the way, and the tests check what the compiler ships and what the browser loads for them (which bundles and chunks hold which implementations). Fixtures for each library go in a folder of their own under `app/`.

## Running the tests

```sh
mix deps.get
mix test
```

## Running the server

```sh
mix deps.get
mix phx.server
```

Open http://localhost:4000 with a page's path appended (see `mix holo.routes`).
