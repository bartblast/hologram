# Sync benchmark

How many connected clients one node can keep in sync, how long a committed write takes to reach them, and how much database work each write costs. It runs a small Hologram app with real entities, pages and read rules, and fake clients that connect over HTTP and SSE the way a browser does. It talks to sync only through the wire, so it keeps running when sync's internals change, and figures taken before and after a change compare.

## Cases

1. `board`: a shared board where every client sees every write.
2. `tenants`: a multi-tenant app where each write reaches a few clients.
3. `access`: one write that changes who may read thousands of rows, like archiving a big project.
4. `deploy`: a deploy that changes the read rules, so every returning client is sent everything again, all at once.
5. `lock`: whether the lock Postgres takes when a transaction that called `pg_notify` commits caps how many writes per second get through.

`boot` only starts and stops the server node, `seed` seeds the board, and `smoke` also connects a few clients to it, to check the setup.

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
3. Postgres 15 or newer, on localhost with the `postgres`/`postgres` user. The driver creates the `hologram_sync_benchmark` database when it's missing.
4. Every client holds a socket in the driver and one in the server, so raise the open file limit for big client counts, for example `ulimit -n 65536`.
5. macOS caps a listen backlog at `kern.ipc.somaxconn`, 128 by default, which the `deploy` case's burst of connects overflows. Raise it with `sudo sysctl -w kern.ipc.somaxconn=4096`.
6. The first compile in a fresh checkout runs `npm install` in the repo's `assets` folder, which can rewrite `assets/package-lock.json`. Undo that change.

## Reading the results

1. Each case's section names the commit, the machine and the database it ran on. Figures from different machines don't compare.
2. A step of the board and tenants cases connects its clients, times their downloads, then makes 20 unmeasured warm-up writes, 5 single writes, each waited on until every client it should reach has it, and steady writes at a fixed rate. A step of the access case makes 3 warm-up writes, then archives the project and unarchives it, each timed until every client has heard of every doc. Last, either kind reads 10 idle seconds, and the idle rate of server CPU and database work is taken off every other phase, since heartbeats and the server's polls run whatever the writes do.
3. Clients per node is the largest step that passed. It depends on the write rate, so the single writes' figures, which don't, sit beside it.
4. "Fills restarted" counts downloads the server cut short and the client started over, as a browser does. Today these are the SSE heap cap killing streams (#1635). "Heap kills" counts the kills in the server's log over the whole step, so the two agree unless a stream was killed after its download.
5. Server CPU is the busy time of the server node's schedulers. The clients and Postgres share the machine's cores, and a scheduler counts as busy while the OS has it waiting for one, so the figure overstates under load. On a shared board, CPU per write per client is judging the rows for each client and encoding their frames together.
6. Database figures come from Postgres's own counters for the whole database. Those count the server's polls too, which is why the idle rate comes off them. They leave out autovacuum, which the benchmark turns off for its tables and replaces with a `VACUUM ANALYZE` between steps. A step where autovacuum ran anyway says so. Per write, they're reliable over the steady writes. Rows fetched stays noisy at this size. For a download, only rows scanned is shown: a download is short against the waits around it, so its other counters drown in the idle rate.
7. "Leaked" counts steady writes that reached a client whose user may not read the row, which should always be 0. "Streams lost" counts streams that ended after their download. "Sessions cut" counts sync sessions the server stopped for falling behind its rounds, from the server's log, since today such a session's stream stays open and the client is never told. Either way the client stops getting writes, so they count as missing, and the step's per-write figures cover sessions that stopped working partway.
8. "KB per client" is how far the server node's memory grew from before the clients connected to after their downloads, divided by the clients, from 20 clients up. Only the reading before is taken after collecting garbage, so the figure includes garbage. The server isn't made to collect after the downloads, since collecting the streams' processes would change what happens next: a stream's process is killed past a heap size (#1635). The access case's "memory rise" is the whole node's highest reading, every 20 ms, above the one taken just before its write, so memory freed meanwhile offsets it, and the unarchive starts from whatever the archive left.
9. Run it on a quiet machine. At 1 client the p99 is the slowest delivery of the step, 60 at the default rate and length, so one stall from other work fails the step.

## Results

<!-- results -->
None yet.
<!-- /results -->
