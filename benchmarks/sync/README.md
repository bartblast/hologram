# Sync benchmark

How many connected clients one node can keep in sync, how long a committed write takes to reach them, and how much database work each write costs. It runs a small Hologram app with real entities, pages and read rules, and fake clients that connect over HTTP and SSE the way a browser does. It talks to sync only through the wire, so it keeps running when sync's internals change, and figures taken before and after a change compare.

## Cases

1. `board`: a shared board where every client sees every write.
2. `tenants`: a multi-tenant app where each write reaches a few clients.
3. `access`: one write that changes who may read thousands of rows, like archiving a big project.
4. `deploy`: a deploy that changes the read rules, so every returning client is sent everything again, all at once.
5. `lock`: whether the lock Postgres takes when a transaction that called `pg_notify` commits caps how many writes per second get through.

`boot` only starts and stops the server node, to check the setup.

## How it runs

The driver is the `mix run` process. It starts the server as a separate node (a `:peer`) and runs the clients itself, so the server's CPU and memory figures leave out what the clients cost. Both share the machine with Postgres, so they compete for cores. The results name the machine.

The app depends on Hologram by path, so it measures the working tree it sits in.

## Running it

In this folder:

```
mix deps.get
HOLOGRAM_START=1 mix run --no-start bench.exs --case boot
```

1. `HOLOGRAM_START=1` makes the compile run the Hologram compiler, which builds the pages' windows and bundles. Without it the driver refuses to start.
2. `--no-start` skips booting the app on the driver, which only the server node needs. The driver never starts Hologram either way, so the server node is the only node syncing.
3. Postgres 14 or newer, on localhost with the `postgres`/`postgres` user. The driver creates the `hologram_sync_benchmark` database when it's missing.
4. Every client holds a socket in the driver and one in the server, so raise the open file limit for big client counts, for example `ulimit -n 65536`.
5. macOS caps a listen backlog at `kern.ipc.somaxconn`, 128 by default, which the `deploy` case's burst of connects overflows. Raise it with `sudo sysctl -w kern.ipc.somaxconn=4096`.
6. The first compile in a fresh checkout runs `npm install` in the repo's `assets` folder, which can rewrite `assets/package-lock.json`. Undo that change.

## Results

<!-- results -->
None yet.
<!-- /results -->
