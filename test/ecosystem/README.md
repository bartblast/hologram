# Hologram Ecosystem Tests

End-to-end tests for Hologram used together with libraries of the Elixir ecosystem.

Today it covers the data flow analysis' rules for the data framework: the fixture resources in `app/ash` are reached through the interfaces generated on them, and the tests check what the compiler makes of them (which types reach the client bundles). Fixtures for other libraries go in folders of their own under `app/`.

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
