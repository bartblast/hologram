# Sync benchmark

How many connected clients one node can keep in sync, how long a committed write takes to reach them, and how much database work each write costs. It runs a small Hologram app with real entities, pages and read rules, and fake clients that connect over HTTP and SSE the way a browser does. It talks to sync only through the wire, so it keeps running when sync's internals change, and figures taken before and after a change compare.

## Cases

1. `board`: a shared board where every client sees every write. `board_roles` is the same board read through a role on it.
2. `tenants`: a multi-tenant app where each write reaches a few clients.
3. `access`: one write that changes who may read thousands of rows, like archiving a big project.
4. `deploy` and `deploy_tenants`: a deploy that changes the read rules, on the board's or the tenants' data, so every returning client is sent everything again, all at once.
5. `lock`: whether the lock Postgres takes when a transaction that called `pg_notify` commits caps how many writes per second get through.

Each takes options for its sizes, limits and client counts, like `--clients 1,10,100`, `--cards`, `--docs`, `--refill-limit` or `--lock-duration`, listed with their defaults at the top of `lib/hologram_sync_benchmark/driver.ex`. For `lock`, `--clients` gives how many writers write at once. `lock` measures the lock for the whole Postgres server, so run it with nothing else writing to that server.

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

1. Each case's section names the commit, the machine and the database it ran on, and the machine's load average when the run started. Figures from different machines don't compare, and timings taken under load come out slower than the node is. Run back to back, a case's load average includes the one before it, so leave a minute between cases.
2. A step of the board and tenants cases connects its clients, times their downloads, then makes 20 unmeasured warm-up writes, 5 single writes, each waited on until every client it should reach has it, and steady writes at a fixed rate. A step of the access case makes 3 warm-up writes, then archives the project and unarchives it, each timed until every client has heard of every doc. Last, either kind reads 10 idle seconds, and the idle rate of server CPU and database work is taken off every other phase, since heartbeats and the server's polls run whatever the writes do.
3. Clients per node is the largest step that passed. It depends on the write rate, so the single writes' figures, which don't, sit beside it. A step stops, and the sweep with it, when the server node's memory passes `--memory-limit`, 4 GB by default, so a run can't exhaust the machine. The limit is fixed rather than a share of the machine's memory, so a step stopped at it means the node passed 4 GB of Erlang memory on any machine, which is somewhat below what the OS counts for it.
4. "Fills restarted" counts downloads the server cut short and the client started over, as a browser does. Today these are the SSE heap cap killing streams (#1635). "Heap kills" counts the kills in the server's log over the whole step. The two differ when a stream is killed after its download, or killed again before its restart got going.
5. Server CPU is the busy time of the server node's schedulers. The clients and Postgres share the machine's cores, and a scheduler counts as busy while the OS has it waiting for one, so the figure overstates under load, even past the cores times the time it covers. On a shared board, CPU per write per client is judging the rows for each client and encoding their frames together.
6. Database figures come from Postgres's own counters for the whole database. Those count the server's polls too, which is why the idle rate comes off them. They leave out autovacuum, which the benchmark turns off for its tables and replaces with a `VACUUM ANALYZE` between steps. A step where autovacuum ran anyway says so. Per write, they're reliable over the steady writes. They're left out, with CPU per write, of a step that missed deliveries, lost streams or had sessions cut, since they'd cover less work than the writes caused. Rows fetched stays noisy at this size. A download is short against the waits around it, so its counters drown in the idle rate and aren't shown, except for the deploy cases, whose refills are big enough to show.
7. "Leaked" counts steady writes that reached a client whose user may not read the row, which should always be 0. "Streams lost" counts streams that ended after their download. "Sessions cut" counts sync sessions the server stopped for falling behind its rounds, from the server's log, since today such a session's stream stays open and the client is never told. Either way the client stops getting writes, so they count as missing.
8. "KB per client" is how far the server node's memory grew from before the clients connected to after their downloads, divided by the clients, from 20 clients up. Only the reading before is taken after collecting garbage, so the figure includes garbage. The server isn't made to collect after the downloads, since collecting the streams' processes would change what happens next: a stream's process is killed past a heap size (#1635). The access case's "memory rise" is the whole node's highest reading, every 20 ms, above the one taken just before its write, so memory freed meanwhile offsets it, and the unarchive starts from whatever the archive left.
9. A deploy step makes no writes. It prepares its clients, then connects them all at once, each greeting with a policy hash that isn't the server's and no cursor. The server sends each its rules and then everything it may read, as it does for a tab coming back after a deploy whose cursor names other rules. "Last refill" runs from the first connect to the last client holding its whole pot, restarted downloads (#1635) and connect retries included. It's N cold fills at once: after the pivot a returning browser reports what it holds, so a real refill may cost less. A real browser also sends its replica id and token, which costs the server one pooled query per client before the session starts. These clients make no writes, so they send none, and the figures leave those queries out.
10. Run it on a quiet machine. At 1 client the p99 is the slowest delivery of the step, 60 at the default rate and length, so one stall from other work fails the step.

## Results

<!-- results -->
<!-- case:board -->
### Shared board

Run 2026-11-15 16:39 UTC on commit d1837e12f, Apple M1 Pro, 10 cores, 16 GB, macOS 26.6.2, load average 43.73 when the run started, PostgreSQL 15.14 (Homebrew), synchronous_commit on, fsync on, wal_sync_method open_datasync, Elixir 1.20.0 on OTP 29.

- 2000 cards read with a bare `allow :read`, which lets every client read every card, so every write reaches every client
- anonymous clients, steps of 1, 2, 5, 10, 20, 50, 100, 200, 500, 1000, 2000, 5000 clients
- a step stops, and the sweep with it, when the server node's memory passes 4 GB
- steady writes at 2 per second for 30 s
- a step passes when every client fills within 300 s and every write reaches every client it should and no other, with the steady writes' p99 within 1000 ms

Clients per node: **100 (1 fill restarted, #1635; 200 stopped at the 4 GB memory limit, the server node holding 4.0 GB)**

#### Fill

| Clients | Filled | Fill p50 ms | Fill p99 ms | Fills restarted | Heap kills | Server CPU ms | KB per client |
|---|---|---|---|---|---|---|---|
| 1 | 1/1 | 212 | 212 | 0 | 0 | 65.2 | - |
| 2 | 2/2 | 79.0 | 80.7 | 0 | 0 | 82.8 | - |
| 5 | 5/5 | 59.8 | 66.2 | 0 | 0 | 192 | - |
| 10 | 10/10 | 74.3 | 75.5 | 0 | 0 | 313 | - |
| 20 | 20/20 | 132 | 398 | 1 | 1 | 1030 | 12325 |
| 50 | 50/50 | 306 | 557 | 1 | 1 | 4174 | 12255 |
| 100 | 100/100 | 505 | 531 | 1 | 1 | 7941 | 12146 |

#### Single writes, median of 5

| Clients | To the last client ms | Server CPU ms | Cut short |
|---|---|---|---|
| 1 | 55.2 | 25.4 | 0 |
| 2 | 24.7 | 33.2 | 0 |
| 5 | 22.0 | 55.7 | 0 |
| 10 | 27.0 | 135 | 0 |
| 20 | 43.6 | 378 | 0 |
| 50 | 92.4 | 1344 | 0 |
| 100 | 191 | 3160 | 0 |

#### Steady writes

| Clients | Writes/s | Delivered | p50 ms | p95 ms | p99 ms | Max ms | Leaked | Streams lost | Sessions cut | CPU ms per write | CPU ms per write per client | DB commits per write | DB rows scanned per write | DB rows fetched per write | DB ms per write | Step passed |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 2.00 | 60/60 | 22.8 | 58.0 | 89.8 | 89.8 | 0 | 0 | 0 | 25.0 | 25.0 | 7.03 | 2105 | 48.3 | 9.67 | yes |
| 2 | 2.00 | 120/120 | 21.2 | 32.0 | 71.8 | 71.9 | 0 | 0 | 0 | 35.3 | 17.6 | 7.05 | 2121 | 43.6 | 5.49 | yes |
| 5 | 2.00 | 300/300 | 20.7 | 24.4 | 33.8 | 35.8 | 0 | 0 | 0 | 51.8 | 10.4 | 7.05 | 2111 | 34.1 | 5.20 | yes |
| 10 | 2.00 | 600/600 | 25.4 | 32.6 | 38.7 | 40.2 | 0 | 0 | 0 | 127 | 12.7 | 7.22 | 2072 | 32.4 | 5.90 | yes |
| 20 | 2.00 | 1200/1200 | 34.2 | 46.6 | 51.8 | 55.6 | 0 | 0 | 0 | 334 | 16.7 | 7.14 | 2101 | 24.7 | 4.93 | yes |
| 50 | 2.00 | 3000/3000 | 73.0 | 101 | 117 | 120 | 0 | 0 | 0 | 1071 | 21.4 | 7.09 | 2062 | 16.5 | 4.16 | yes |
| 100 | 2.00 | 6000/6000 | 138 | 198 | 239 | 283 | 0 | 0 | 0 | 2532 | 25.3 | 7.18 | 2064 | 12.7 | 5.67 | yes |
<!-- /case:board -->

<!-- case:board_roles -->
### Shared board read by role

Run 2026-11-15 16:30 UTC on commit d1837e12f, Apple M1 Pro, 10 cores, 16 GB, macOS 26.6.2, load average 12.40 when the run started, PostgreSQL 15.14 (Homebrew), synchronous_commit on, fsync on, wal_sync_method open_datasync, Elixir 1.20.0 on OTP 29.

- 2000 cards read with `allow :read, via: {:read, board}` on cards and `allow :read, to: :viewer` on the board, which lets every client read every card, so every write reaches every client
- signed-in clients, each user holding the viewer role on the board, steps of 1, 2, 5, 10, 20, 50, 100, 200, 500, 1000, 2000, 5000 clients
- a step stops, and the sweep with it, when the server node's memory passes 4 GB
- steady writes at 2 per second for 30 s
- a step passes when every client fills within 300 s and every write reaches every client it should and no other, with the steady writes' p99 within 1000 ms

Clients per node: **below 1 (1 client failed: 2 single writes never reached everyone, 55 deliveries missing, 1 session cut, steady p99 2311 ms)**

#### Fill

| Clients | Filled | Fill p50 ms | Fill p99 ms | Fills restarted | Heap kills | Server CPU ms | KB per client |
|---|---|---|---|---|---|---|---|
| 1 | 1/1 | 1085 | 1085 | 0 | 0 | 496 | - |

#### Single writes, median of 5

| Clients | To the last client ms | Server CPU ms | Cut short |
|---|---|---|---|
| 1 | 2374 | 918 | 2 |

#### Steady writes

| Clients | Writes/s | Delivered | p50 ms | p95 ms | p99 ms | Max ms | Leaked | Streams lost | Sessions cut | CPU ms per write | CPU ms per write per client | DB commits per write | DB rows scanned per write | DB rows fetched per write | DB ms per write | Step passed |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 2.00 | 5/60 | 1717 | 2311 | 2311 | 2311 | 0 | 0 | 1 | - | - | - | - | - | - | no |
<!-- /case:board_roles -->

<!-- case:tenants -->
### Multi-tenant app

Run 2026-11-15 16:34 UTC on commit d1837e12f, Apple M1 Pro, 10 cores, 16 GB, macOS 26.6.2, load average 10.70 when the run started, PostgreSQL 15.14 (Homebrew), synchronous_commit on, fsync on, wal_sync_method open_datasync, Elixir 1.20.0 on OTP 29.

- 20 tenants of 5 members with 100 tasks each, 2000 tasks in all, read with `allow :read, when: any(member <- tenant.members, member.user_id == user_id())`, so a write reaches the clients of its tenant's members
- signed-in clients, one per user, filling whole tenants in order, steps of 1, 2, 5, 10, 20, 50, 100 clients
- a step stops, and the sweep with it, when the server node's memory passes 4 GB
- steady writes at 2 per second for 30 s
- a step passes when every client fills within 300 s and every write reaches every client it should and no other, with the steady writes' p99 within 1000 ms

Clients per node: **below 1 (1 client failed: 59 deliveries missing, 1 session cut, steady p99 6807 ms)**

#### Fill

| Clients | Filled | Fill p50 ms | Fill p99 ms | Fills restarted | Heap kills | Server CPU ms | KB per client |
|---|---|---|---|---|---|---|---|
| 1 | 1/1 | 3642 | 3642 | 0 | 0 | 1089 | - |

#### Single writes, median of 5

| Clients | To the last client ms | Server CPU ms | Cut short |
|---|---|---|---|
| 1 | 2004 | 724 | 0 |

#### Steady writes

| Clients | Writes/s | Delivered | p50 ms | p95 ms | p99 ms | Max ms | Leaked | Streams lost | Sessions cut | CPU ms per write | CPU ms per write per client | DB commits per write | DB rows scanned per write | DB rows fetched per write | DB ms per write | Step passed |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 1.99 | 1/60 | 6807 | 6807 | 6807 | 6807 | 0 | 0 | 1 | - | - | - | - | - | - | no |
<!-- /case:tenants -->

<!-- case:access -->
### One write changing access to many rows

Run 2026-11-15 16:07 UTC on commit d1837e12f, Apple M1 Pro, 10 cores, 16 GB, macOS 26.6.2, load average 16.63 when the run started, PostgreSQL 15.14 (Homebrew), synchronous_commit on, fsync on, wal_sync_method open_datasync, Elixir 1.20.0 on OTP 29.

- one project with 5000 docs read with `allow :read, when: project.archived == false and any(member <- project.members, member.user_id == user_id())`, every member connected
- a step archives the project, hiding every doc from every client, then unarchives it, and passes when every client fills within 300 s and has heard of every doc within 10 s each way
- signed-in clients, one per member of the project, steps of 1, 2, 5, 10, 20, 50, 100 clients
- a step stops, and the sweep with it, when the server node's memory passes 4 GB

Clients per node: **below 1 (11 fills restarted, #1635; 1 client failed: 1 never filled)**

#### Fill

| Clients | Filled | Fill p50 ms | Fill p99 ms | Fills restarted | Heap kills | Server CPU ms | KB per client |
|---|---|---|---|---|---|---|---|
| 1 | 0/1 | - | - | 11 | 13 | 11769 | - |

#### Archive, then unarchive

| Clients | Hide ms | Hide CPU ms | Hide DB commits | Hide DB rows scanned | Hide DB ms | Show ms | Show CPU ms | Show DB commits | Show DB rows scanned | Show DB ms | Hide memory rise MB | Show memory rise MB | Step passed |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | - | - | - | - | - | - | - | - | - | - | - | - | no |
<!-- /case:access -->

<!-- case:deploy -->
### Reconnect after a rules deploy, shared board

Run 2026-11-15 16:14 UTC on commit d1837e12f, Apple M1 Pro, 10 cores, 16 GB, macOS 26.6.2, load average 7.11 when the run started, PostgreSQL 15.14 (Homebrew), synchronous_commit on, fsync on, wal_sync_method open_datasync, Elixir 1.20.0 on OTP 29.

- 2000 cards read with a bare `allow :read`, which lets every client read every card
- anonymous clients, connecting all at once with a stale policy hash and no cursor, steps of 10, 100, 200, 500, 1000, 5000 clients
- a step stops, and the sweep with it, when the server node's memory passes 4 GB
- a step passes when every client holds its whole pot again within 60 s of the first connect

Clients per node: **200 (4 fills restarted, #1635; 500 stopped at the 4 GB memory limit, the server node holding 4.0 GB)**

#### Refill

| Clients | Refilled | Rules sent | Last refill ms | Refill p50 ms | Refill p99 ms | Connect retries | Fills restarted | Heap kills | Server CPU s | DB rows scanned | Memory rise MB | KB per client | Step passed |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 10 | 10/10 | 10 | 110 | 110 | 110 | 0 | 0 | 0 | 0.44 | 1557 | 151 | - | yes |
| 100 | 100/100 | 100 | 570 | 566 | 567 | 0 | 0 | 0 | 8.35 | 3446 | 1346 | 12269 | yes |
| 200 | 200/200 | 200 | 1509 | 1435 | 1488 | 0 | 4 | 4 | 23.3 | 2187 | 2479 | 12193 | yes |
<!-- /case:deploy -->

<!-- case:deploy_tenants -->
### Reconnect after a rules deploy, multi-tenant app

Run 2026-11-15 16:21 UTC on commit d1837e12f, Apple M1 Pro, 10 cores, 16 GB, macOS 26.6.2, load average 11.37 when the run started, PostgreSQL 15.14 (Homebrew), synchronous_commit on, fsync on, wal_sync_method open_datasync, Elixir 1.20.0 on OTP 29.

- 20 tenants of 5 members with 100 tasks each, 2000 tasks in all, read with `allow :read, when: any(member <- tenant.members, member.user_id == user_id())`
- signed-in clients, one per user, filling whole tenants in order, connecting all at once with a stale policy hash and no cursor, steps of 10, 100 clients
- a step stops, and the sweep with it, when the server node's memory passes 4 GB
- a step passes when every client holds its whole pot again within 60 s of the first connect

Clients per node: **at least 100**

#### Refill

| Clients | Refilled | Rules sent | Last refill ms | Refill p50 ms | Refill p99 ms | Connect retries | Fills restarted | Heap kills | Server CPU s | DB rows scanned | Memory rise MB | KB per client | Step passed |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 10 | 10/10 | 10 | 2899 | 2875 | 2898 | 0 | 0 | 0 | 9.51 | 504772 | 114 | - | yes |
| 100 | 100/100 | 100 | 24216 | 24181 | 24211 | 0 | 0 | 0 | 115 | 5007266 | 1004 | 10030 | yes |
<!-- /case:deploy_tenants -->

<!-- case:lock -->
### The pg_notify commit lock

Run 2026-11-15 16:25 UTC on commit d1837e12f, Apple M1 Pro, 10 cores, 16 GB, macOS 26.6.2, load average 9.95 when the run started, PostgreSQL 15.14 (Homebrew), synchronous_commit on, fsync on, wal_sync_method open_datasync, Elixir 1.20.0 on OTP 29.

- 1, 2, 4, 8, 16 and 32 writers at once, for 10 s each
- plain and notify writers run on connections of the driver's own, into a scratch table, notify with one connection listening; Hologram's run on the server node, with a pool as big as its writers plus 5 and no client connected
- the lock is one for the whole server; "held" is the share of samples, every 50 ms, it was held in, "queued" the writers waiting for it on average, as a share of all writers, and "other databases" the share of samples a holder was in another database, which measures what else on the server notifies
- a notifying commit costs more than a plain one even with one writer, where nothing queues, so only the growth past the 1-writer row can be the lock

Verdict: **Notifying commits peak at 6694 per second, with 32 writers and the lock held 99% of the time. With 16 and 32 writers the lock was held nearly all the time, so it caps them, at about 6729 per second. Hologram's writes peak at 3246 per second, with 16 writers and the lock held 55% of the time. The lock was held at most 84% of the time, so it doesn't cap them.**

#### Writes per second by writers at once

| Writers | Plain commits/s | Notify commits/s | Notify lock held | Notify writers queued | Hologram writes/s | Hologram lock held | Hologram writers queued | Other databases holding it |
|---|---|---|---|---|---|---|---|---|
| 1 | 3449 | 1519 | 12% | 0% | 666 | 6% | 0% | 0% |
| 2 | 5433 | 2677 | 33% | 9% | 1197 | 13% | 2% | 0% |
| 4 | 7559 | 4200 | 33% | 3% | 1515 | 26% | 8% | 0% |
| 8 | 10223 | 6466 | 76% | 18% | 3047 | 35% | 6% | 0% |
| 16 | 13148 | 5831 | 97% | 37% | 3246 | 55% | 9% | 0% |
| 32 | 12298 | 6694 | 99% | 74% | 2650 | 84% | 34% | 0% |
<!-- /case:lock -->
<!-- /results -->
