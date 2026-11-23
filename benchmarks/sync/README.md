# Sync benchmark

How many connected clients one node can keep in sync, how long a committed write takes to reach them, and how much database work each write costs. It runs a small Hologram app with real entities, pages and read rules, and fake clients that connect over HTTP and SSE the way a browser does. It talks to sync only through the wire, so it keeps running when sync's internals change, and figures taken before and after a change compare.

## Cases

1. `board`: a shared board where every client sees every write. `board_roles` is the same board read through a role on it.
2. `tenants`: a multi-tenant app where each write reaches a few clients.
3. `access`: one write that changes who may read thousands of rows, like archiving a big project.
4. `deploy` and `deploy_tenants`: a deploy that changes the read rules, on the board's or the tenants' data, so every returning client is sent everything again, all at once.
5. `reconnect` and `reconnect_tenants`: a deploy that changes neither the data model nor the rules, on the board's or the tenants' data, so every client comes back within seconds with the place it had and is told only what it missed.
6. `catchups`: the same reconnect wave at 1, 2, 4, 8 and 16 catch-ups at once (`--catchups`, with `--clients` as its one client count, 1,000 by default), which is what sets how many a node should run.
7. `session_memory`: what one connected client's sync session costs a node while it sits idle, for clients holding 1,000, 10,000 and 100,000 rows (`--rows`).
8. `backlog`: a long writing transaction holding up the dispatcher while many clients keep writing, with how long the read of the batches committed meanwhile takes (`--backlog-rows`, `--replicas`). It holds a transaction open, which stalls sync in every database on the Postgres server, so it refuses a server with other databases in use. Give it one of its own with `BENCH_PG_PORT=<port>`.
9. `big_set`: one write touching a row with a very big set, like linking a post to a tag with 300,000 posts (`--set-sizes`).
10. `lock`: whether the lock Postgres takes when a transaction that called `pg_notify` commits caps how many writes per second get through.

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

1. `HOLOGRAM_START=1` makes the compile run the Hologram compiler, which builds the pages' types and bundles. Without it the driver refuses to start.
2. `--no-start` keeps the app and Hologram from booting on the driver, which would make it a second node syncing against the same database. A run without it fails: in the driver, or in Hologram's boot with an error saying the database belongs to the "test" env.
3. Postgres 15 or newer, on localhost with the `postgres`/`postgres` user. The driver creates the `hologram_sync_benchmark` database when it's missing.
4. Every client holds a socket in the driver and one in the server, so raise the open file limit for big client counts, for example `ulimit -n 65536`.
5. macOS caps a listen backlog at `kern.ipc.somaxconn`, 128 by default, which the burst of connects in the `deploy`, `reconnect` and `catchups` cases overflows. Raise it with `sudo sysctl -w kern.ipc.somaxconn=4096`.
6. The first compile in a fresh checkout runs `npm install` in the repo's `assets` folder, which can rewrite `assets/package-lock.json`. Undo that change.

## Reading the results

1. Each case's section names the commit, the machine and the database it ran on, and the machine's load average when the run started. Figures from different machines don't compare, and timings taken under load come out slower than the node is. Run back to back, a case's load average includes the one before it, so leave a minute between cases.
2. A step of the board and tenants cases connects its clients, times their downloads, then makes 20 unmeasured warm-up writes, 5 single writes, each waited on until every client it should reach has it, and steady writes at a fixed rate. A step of the access case makes 3 warm-up writes, then archives the project and unarchives it, each timed until every client has heard of every doc. Last, either kind reads 10 idle seconds, and the idle rate of server CPU and database work is taken off every other phase, since heartbeats and the server's polls run whatever the writes do.
3. Clients per node is the largest step that passed. It depends on the write rate, so the single writes' figures, which don't, sit beside it. A step stops, and the sweep with it, when the server node's memory passes `--memory-limit`, 4 GB by default, so a run can't exhaust the machine. The limit is fixed rather than a share of the machine's memory, so a step stopped at it means the node passed 4 GB of Erlang memory on any machine, which is somewhat below what the OS counts for it.
4. "Fills restarted" counts downloads the server cut short and the client started over, as a browser does, whether a heap kill or a session cut (item 7) ended them. "Heap kills" counts the kills in the server's log over the whole step, including any after a download.
5. Server CPU is the busy time of the server node's schedulers. The clients and Postgres share the machine's cores, and a scheduler counts as busy while the OS has it waiting for one, so the figure overstates under load, even past the cores times the time it covers. On a shared board, CPU per write per client is judging the rows for each client and encoding their frames together.
6. Database figures come from Postgres's own counters for the whole database. Those count the server's polls too, which is why the idle rate comes off them. They leave out autovacuum, which the benchmark turns off for its tables and replaces with a `VACUUM ANALYZE` between steps. A step where autovacuum ran anyway says so. Per write, they're reliable over the steady writes. They're left out, with CPU per write, of a step that missed deliveries, lost streams or had sessions cut, since they'd cover less work than the writes caused. Rows fetched stays noisy at this size. A download is short against the waits around it, so its counters drown in the idle rate and aren't shown, except for the deploy cases, whose refills are big enough to show.
7. "Leaked" counts steady writes that reached a client whose user may not read the row, which should always be 0. A single write that leaks fails the step too, and its note says so. "Streams lost" counts streams that ended after their download. "Sessions cut" counts sync sessions the server stopped because their stream took no frames for a minute, from the server's log, since the client only sees its stream end. The server ends a cut session's stream once it has written the frames already queued, or a write fails. A cut after the download stops the client getting writes, so they count as missing, and it counts as a stream lost too if the stream ended before the steady writes' figures were read. A cut during the download counts as a restarted fill, and the client goes on.
8. "KB per client" is how far the server node's memory grew from before the clients connected to after their downloads, divided by the clients, from 20 clients up. Only the reading before is taken after collecting garbage, so the figure includes garbage. The server isn't made to collect after the downloads, since collecting the streams' processes would change what happens next: a stream's process is killed past a heap size (#1635). The access case's "memory rise" is the whole node's highest reading, every 20 ms, above the one taken just before its write, so memory freed meanwhile offsets it, and the unarchive starts from whatever the archive left.
9. A deploy step makes no writes. It prepares its clients, then connects them all at once, each greeting with a policy hash that isn't the server's and no cursor. The server sends each its rules and then everything it may read, as it does for a tab coming back after a deploy whose cursor names other rules. "Last refill" runs from the first connect to the last client holding its whole pot, restarted downloads and connect retries included. It's N cold fills at once, as a real refill is, since a cursor naming other rules gets its client everything again. A real browser also sends its replica id and token, which costs the server one pooled query per client before the session starts and one more per entity type its fill reads. These clients make no writes, so they send none, and the figures leave those queries out.
10. Run it on a quiet machine. At 1 client the p99 is the slowest delivery of the step, 60 at the default rate and length, so one stall from other work fails the step.
11. A reconnect step runs on two server nodes. The first fills the clients, which then leave, and takes `--gap-writes` writes while they're away. The second is the deployed node, started cold, and only its work is measured. Each client comes back at a random moment within `--wave-spread-ms`, greeting with its replica identity as a browser does. The default, 5,000, is about the gentlest wave browsers make: their longest retry delay, before its 25% jitter, reached after a restart of over about 8 s. A short restart or a rolling deploy brings every client back within a few hundred milliseconds, so take the figures at `--wave-spread-ms 250` as well. A spread under a second writes its own section, named `_burst`, and a run with `--wave-writes` above 0 one named `_writes`, beside the plain one. "Last caught up" runs from the first client back to the last one told it holds everything, so it includes the spread, "after the last return" from the last client back to that, and "own wait" from a client's own return to that, shown only when every client finished. "App" figures are one page render with one primary key lookup through the app's pool, 20 a second over four connections, each timed from when it was due, so a stall counts against the requests behind it. "Peak sync backends" and "peak other backends" are the most connections of sync's own pool and of everything else seen running a statement at once, sampled every 200 ms while the deployed node runs, so a shorter statement can be missed. "Heap kills" and "sessions cut" count the fill's and the wave's. "Return restarts" counts a return's refused connects and lost streams. CPU and database figures are left out of a step where a client never caught up, or where a write made during the wave hadn't reached every client it should when the wait for it ended, since the node may still be at work in the idle window they're corrected by. That wait is 10 s, and a write that misses it fails the step. A client told to start over fails the step. The writes carry no browser batch, so the catch-up's read of a client's own later batches comes back empty, which a real gap's needn't. For the tenants case, name the size with `--tenants` and `--members`, since the defaults hold only 100 users.
12. With `--wave-writes` above 0, a reconnect step adds a "Returning sessions" table, read from the sessions at the deployed node's gate. Reading them costs the node a few percent of a core with thousands waiting, so take a wave's CPU from a run without it. A session waiting for its turn hasn't joined the node's sessions, so no batch reaches it, and its figure is a bare process, from a sample of 20 every 250 ms. A session holding a turn keeps every batch that arrives until it's caught up, in its mailbox, read every 20 ms, so a shorter turn can be missed, and one that's seen counts as at least 20 ms, so "turn p50" leans high with a small gap. Its memory is the process's and the binaries it refers to, so a binary several sessions share counts in each, and "MB catching up, most at once" can overstate, while a binary in a message still queued can be left out. To see the mailbox grow, run a big gap with a write rate, like `--cards 20000 --gap-writes 4000 --wave-writes 20 --wave-limit 40`. Those writes also land in the wave's database figures.
13. `session_memory` reads each idle session as it stands and again after collecting that session's garbage, and takes the median across its clients. "First arrival KB" and "Returning KB" are what an idle session takes as it stands, and the collected figures are its floor. A first arrival collects just before its last frame and a returning session hibernates once it's caught up, so their heaps differ at that point, and the two compare on the collected figures. Its memory is the process's and the off-heap binaries it refers to. Those are the packed ids of what it holds plus a few other bytes, so "Of which off-heap binaries KB" is what grows with the rows, and "rest" is what a session costs whatever it holds. A type's packed ids of 64 bytes or less, which is 4 ids, stay on the heap and count under "rest". The app's build has no permission checks in the browser. With them, a first arrival also keeps a verdict entry per row, and a returning session doesn't. "Stream KB" is the process serving the client's stream, read without collecting it, since it's killed past a heap size. "Returning" is the same client after leaving and coming back with nothing missed, whose session builds what it holds by reading its ids rather than by being told. "Returning, back to caught up" is a whole return for one client alone: its connection, handshake, stream, id reads and final frame. "Reading its ids" is that read by itself, the part a shared list for rows everyone may read (#1676) would save.
14. `backlog` holds one transaction open above a marked write, so when that write commits the dispatcher delivers it alone with the whole backlog above it. "Held-up write" runs from that commit to the last client having it, against "ordinary write" with nothing held up, and "memory rise" is the node's highest reading over it. "Read ms, direct" is the read of the batches above it, called by hand five times on the node, the median, as a cross-check on what the delivery pays. "List KB" is the size of what that read returns, which goes to every session, and "list MB across sessions" that times the clients. "Whole backlog" runs from ending the blocking transaction to the last client having the backlog's last write, when the dispatcher reads the whole backlog as one window. A dash means it took longer than 120 s, or a client lost its stream first, which "streams lost" shows, and either is a figure rather than a failed run.
15. `catchups` runs every number whatever the one before it did, with sync's database pool sized to match, as it is by default. The library has no setting for the number, so the benchmark tells the deployed node's gate directly. "Last caught up" can't drop below the wave's spread, however fast the node is, so the number to read is "after the last return": how long the queue took to clear once every client was back. More at once clears it sooner and takes more of the database, so read that against "app p99 during". A run stops counting as that number if the gate restarts during it, since a new gate goes back to the default.
16. `big_set` hides nearly all its posts from the clients with their read rule, so they hold the tag and a few posts, and what's measured is the server reading the set rather than clients downloading it. "Read of the set" is the read each batch touching the tag makes, called by hand on the node, the median of three, and "set MB" what it returns. "Write into it" links a post to the tag, against "write outside it", a write to a post in no set, and "memory rise" is the node's highest reading over the writes into it. Those writes make the dispatcher read the set, but a session scans it only when it drops the tag or is handed it, so the case then hides the tag from every client ("tag dropped") and shows it again ("tag handed back"), each timed from its commit to the last client. Its two entity types join every case's synced types, so every fill and catch-up reads them too, empty outside this case.
17. With `--fill-group`, the `board` and `tenants` cases fill that many clients at a time, each group once the one before is done, and record in a section of their own whose name ends in `_groups`. Without it every client downloads at once, so a step can stop at the memory limit before live sync is measured. Each fill time runs from that client's own connect to its last row, so it shows a group's load and doesn't compare with a fill of every client at once. The fill's CPU shows a dash.
18. A section dated before 2026-11-19 measured sync as it was before it moved to read access (#1601).

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

<!-- case:board_groups -->
### Shared board, filled in groups

Run 2026-11-22 18:16 UTC on commit eb20796a4, Apple M1 Pro, 10 cores, 16 GB, macOS 26.6.2, load average 4.61 when the run started, PostgreSQL 15.14 (Homebrew), synchronous_commit on, fsync on, wal_sync_method open_datasync, Elixir 1.20.0 on OTP 29.

- 2000 cards read with a bare `allow :read`, which lets every client read every card, so every write reaches every client
- anonymous clients, steps of 1, 2, 5, 10, 20, 50, 100, 200, 500, 1000, 2000, 5000 clients
- a step stops, and the sweep with it, when the server node's memory passes 4 GB
- clients fill 20 at a time, each group once the one before is done
- steady writes at 2 per second for 30 s
- a step passes when every client fills within 300 s and every write reaches every client it should and no other, with the steady writes' p99 within 1000 ms

Clients per node: **at least 5000**

#### Fill

| Clients | Filled | Fill p50 ms | Fill p99 ms | Fills restarted | Heap kills | Server CPU ms | KB per client |
|---|---|---|---|---|---|---|---|
| 1 | 1/1 | 82.9 | 82.9 | 0 | 0 | - | - |
| 2 | 2/2 | 77.2 | 77.9 | 0 | 0 | - | - |
| 5 | 5/5 | 83.8 | 85.7 | 0 | 0 | - | - |
| 10 | 10/10 | 95.4 | 105 | 0 | 0 | - | - |
| 20 | 20/20 | 136 | 140 | 0 | 0 | - | 580 |
| 50 | 50/50 | 111 | 149 | 0 | 0 | - | 518 |
| 100 | 100/100 | 90.3 | 146 | 0 | 0 | - | 540 |
| 200 | 200/200 | 100 | 147 | 0 | 0 | - | 529 |
| 500 | 500/500 | 92.7 | 142 | 0 | 0 | - | 545 |
| 1000 | 1000/1000 | 89.3 | 138 | 0 | 0 | - | 541 |
| 2000 | 2000/2000 | 91.3 | 108 | 0 | 0 | - | 525 |
| 5000 | 5000/5000 | 100 | 122 | 0 | 0 | - | 333 |

#### Single writes, median of 5

| Clients | To the last client ms | Server CPU ms | Cut short |
|---|---|---|---|
| 1 | 4.53 | 3.90 | 0 |
| 2 | 4.20 | 4.65 | 0 |
| 5 | 3.92 | 4.88 | 0 |
| 10 | 3.74 | 5.60 | 0 |
| 20 | 5.40 | 5.67 | 0 |
| 50 | 5.59 | 10.4 | 0 |
| 100 | 7.78 | 22.0 | 0 |
| 200 | 5.05 | 24.1 | 0 |
| 500 | 11.4 | 59.9 | 0 |
| 1000 | 17.6 | 108 | 0 |
| 2000 | 28.3 | 196 | 0 |
| 5000 | 52.9 | 404 | 0 |

#### Steady writes

| Clients | Writes/s | Delivered | p50 ms | p95 ms | p99 ms | Max ms | Leaked | Streams lost | Sessions cut | CPU ms per write | CPU ms per write per client | DB commits per write | DB rows scanned per write | DB rows fetched per write | DB ms per write | Step passed |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 2.00 | 60/60 | 3.97 | 5.00 | 5.70 | 5.70 | 0 | 0 | 0 | 4.04 | 4.04 | 7.08 | 137 | 42.4 | 1.85 | yes |
| 2 | 2.00 | 120/120 | 4.04 | 5.07 | 5.39 | 5.46 | 0 | 0 | 0 | 3.99 | 2.00 | 6.80 | 156 | 36.8 | 1.56 | yes |
| 5 | 2.00 | 300/300 | 3.62 | 4.32 | 5.11 | 5.22 | 0 | 0 | 0 | 3.80 | 0.76 | 7.07 | 134 | 44.1 | 1.50 | yes |
| 10 | 2.00 | 600/600 | 3.71 | 4.68 | 5.04 | 5.09 | 0 | 0 | 0 | 4.62 | 0.46 | 6.86 | 147 | 45.5 | 1.62 | yes |
| 20 | 2.00 | 1200/1200 | 3.75 | 4.36 | 4.52 | 4.80 | 0 | 0 | 0 | 4.27 | 0.21 | 6.84 | 107 | 38.0 | 1.42 | yes |
| 50 | 2.00 | 3000/3000 | 4.34 | 5.04 | 5.58 | 5.85 | 0 | 0 | 0 | 10.0 | 0.20 | 7.08 | -0.65 | 1.29 | 1.42 | yes |
| 100 | 2.00 | 6000/6000 | 5.87 | 6.85 | 7.18 | 7.53 | 0 | 0 | 0 | 18.5 | 0.19 | 7.07 | 6.17 | 3.16 | 1.39 | yes |
| 200 | 2.00 | 12000/12000 | 4.43 | 10.1 | 39.6 | 41.5 | 0 | 0 | 0 | 23.7 | 0.12 | 6.93 | 40.7 | 0.70 | 1.21 | yes |
| 500 | 2.00 | 30000/30000 | 9.32 | 12.1 | 12.8 | 14.1 | 0 | 0 | 0 | 66.4 | 0.13 | 6.99 | -7.00 | 0.26 | 1.01 | yes |
| 1000 | 2.00 | 60000/60000 | 12.5 | 17.7 | 18.8 | 20.4 | 0 | 0 | 0 | 113 | 0.11 | 6.93 | 95.4 | 36.6 | 0.99 | yes |
| 2000 | 2.00 | 120000/120000 | 19.2 | 27.8 | 29.5 | 33.4 | 0 | 0 | 0 | 203 | 0.10 | 6.96 | 54.6 | 27.6 | 0.96 | yes |
| 5000 | 2.00 | 300000/300000 | 34.2 | 53.2 | 56.7 | 62.9 | 0 | 0 | 0 | 398 | 0.08 | 7.17 | 97.1 | 28.6 | 1.06 | yes |
<!-- /case:board_groups -->

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

<!-- case:tenants_groups -->
### Multi-tenant app, filled in groups

Run 2026-11-22 18:43 UTC on commit eb20796a4, Apple M1 Pro, 10 cores, 16 GB, macOS 26.6.2, load average 6.14 when the run started, PostgreSQL 15.14 (Homebrew), synchronous_commit on, fsync on, wal_sync_method open_datasync, Elixir 1.20.0 on OTP 29.

- 400 tenants of 5 members with 100 tasks each, 40000 tasks in all, read with `allow :read, when: any(member <- tenant.members, member.user_id == user_id())`, so a write reaches the clients of its tenant's members
- signed-in clients, one per user, filling whole tenants in order, steps of 1, 2, 5, 10, 20, 50, 100, 200, 500, 1000, 2000 clients
- a step stops, and the sweep with it, when the server node's memory passes 4 GB
- clients fill 20 at a time, each group once the one before is done
- steady writes at 2 per second for 30 s
- a step passes when every client fills within 300 s and every write reaches every client it should and no other, with the steady writes' p99 within 1000 ms

Clients per node: **at least 2000**

#### Fill

| Clients | Filled | Fill p50 ms | Fill p99 ms | Fills restarted | Heap kills | Server CPU ms | KB per client |
|---|---|---|---|---|---|---|---|
| 1 | 1/1 | 85.6 | 85.6 | 0 | 0 | - | - |
| 2 | 2/2 | 85.2 | 85.3 | 0 | 0 | - | - |
| 5 | 5/5 | 106 | 119 | 0 | 0 | - | - |
| 10 | 10/10 | 165 | 179 | 0 | 0 | - | - |
| 20 | 20/20 | 295 | 296 | 0 | 0 | - | 282 |
| 50 | 50/50 | 267 | 336 | 0 | 0 | - | 236 |
| 100 | 100/100 | 292 | 331 | 0 | 0 | - | 226 |
| 200 | 200/200 | 247 | 379 | 0 | 0 | - | 185 |
| 500 | 500/500 | 250 | 374 | 0 | 0 | - | 173 |
| 1000 | 1000/1000 | 233 | 353 | 0 | 0 | - | 165 |
| 2000 | 2000/2000 | 232 | 275 | 0 | 0 | - | 160 |

#### Single writes, median of 5

| Clients | To the last client ms | Server CPU ms | Cut short |
|---|---|---|---|
| 1 | 4.91 | 5.07 | 0 |
| 2 | 4.88 | 5.34 | 0 |
| 5 | 7.25 | 6.27 | 0 |
| 10 | 5.97 | 6.70 | 0 |
| 20 | 5.62 | 7.67 | 0 |
| 50 | 8.13 | 8.54 | 0 |
| 100 | 6.79 | 9.65 | 0 |
| 200 | 7.31 | 12.3 | 0 |
| 500 | 11.4 | 20.2 | 0 |
| 1000 | 15.4 | 33.2 | 0 |
| 2000 | 24.5 | 47.5 | 0 |

#### Steady writes

| Clients | Writes/s | Delivered | p50 ms | p95 ms | p99 ms | Max ms | Leaked | Streams lost | Sessions cut | CPU ms per write | CPU ms per write per client | DB commits per write | DB rows scanned per write | DB rows fetched per write | DB ms per write | Step passed |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 2.00 | 60/60 | 5.08 | 6.68 | 8.54 | 8.54 | 0 | 0 | 0 | 1.27 | 1.27 | 6.85 | 68.8 | 17.1 | 1.36 | yes |
| 2 | 2.00 | 120/120 | 5.10 | 6.63 | 7.00 | 7.07 | 0 | 0 | 0 | 5.35 | 2.68 | 7.07 | 98.5 | 42.9 | 1.33 | yes |
| 5 | 2.00 | 300/300 | 5.20 | 7.01 | 7.50 | 7.61 | 0 | 0 | 0 | 4.53 | 0.91 | 6.83 | 84.1 | 35.8 | 1.27 | yes |
| 10 | 2.00 | 300/300 | 5.45 | 7.06 | 7.90 | 8.02 | 0 | 0 | 0 | 4.96 | 0.50 | 7.14 | 92.2 | 44.8 | 1.30 | yes |
| 20 | 2.00 | 300/300 | 5.57 | 7.71 | 8.45 | 8.53 | 0 | 0 | 0 | 7.24 | 0.36 | 7.15 | 105 | 49.6 | 1.34 | yes |
| 50 | 2.00 | 300/300 | 5.12 | 7.65 | 36.1 | 36.2 | 0 | 0 | 0 | 7.29 | 0.15 | 7.20 | 108 | 32.3 | 1.12 | yes |
| 100 | 2.00 | 300/300 | 5.88 | 7.83 | 11.5 | 11.7 | 0 | 0 | 0 | 9.52 | 0.10 | 7.05 | 114 | 34.3 | 1.69 | yes |
| 200 | 2.00 | 300/300 | 7.76 | 9.19 | 10.4 | 10.4 | 0 | 0 | 0 | 14.6 | 0.07 | 7.00 | 140 | 49.6 | 1.41 | yes |
| 500 | 2.00 | 300/300 | 10.9 | 13.4 | 23.1 | 24.2 | 0 | 0 | 0 | 20.2 | 0.04 | 6.76 | 131 | 40.1 | 1.59 | yes |
| 1000 | 2.00 | 300/300 | 15.5 | 17.8 | 18.8 | 19.9 | 0 | 0 | 0 | 30.6 | 0.03 | 7.11 | 106 | 35.0 | 1.78 | yes |
| 2000 | 2.00 | 300/300 | 22.9 | 26.0 | 26.7 | 28.5 | 0 | 0 | 0 | 46.7 | 0.02 | 7.29 | 112 | 40.8 | 2.47 | yes |
<!-- /case:tenants_groups -->

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

<!-- case:reconnect -->
### Reconnect wave after a deploy, shared board

Run 2026-11-22 13:09 UTC on commit c4a007596, Apple M1 Pro, 10 cores, 16 GB, macOS 26.6.2, load average 1.89 when the run started, PostgreSQL 15.14 (Homebrew), synchronous_commit on, fsync on, wal_sync_method open_datasync, Elixir 1.20.0 on OTP 29.

- 2000 cards read with a bare `allow :read`, which lets every client read every card
- 100 writes made while the clients are away, each to a row of its own
- each client comes back at a random moment within 5000 ms, greeting with its replica identity as a browser does
- 0 writes per second while they do, each to a row of its own
- anonymous clients, coming back with their places after a node restart, steps of 100, 500, 1000, 2000, 5000 clients
- a step stops, and the sweep with it, when the server node's memory passes 4 GB
- a step passes when every client is caught up within 120 s of the first one coming back, holding every write it should and no other, with none told to start over

Clients per node: **at least 5000**

#### Wave

| Clients | Caught up | Last caught up ms | After the last return ms | Own wait p50 ms | Own wait p99 ms | Return restarts | Heap kills | Sessions cut | Server CPU s | DB commits | DB rows scanned | DB ms | Peak sync backends | Peak other backends | App p50 ms before | App p99 ms before | App p50 ms during | App p99 ms during | App requests failed | Step passed |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 100 | 100/100 | 4867 | 10.9 | 11.9 | 27.1 | 0 | 0 | 0 | 0.49 | 1542 | 447517 | 119 | 0 | 1 | 5.64 | 9.36 | 3.49 | 7.51 | 0 | yes |
| 500 | 500/500 | 4974 | 11.8 | 10.8 | 32.9 | 0 | 0 | 0 | 2.58 | 8043 | 2209923 | 519 | 2 | 1 | 5.88 | 9.97 | 3.26 | 6.76 | 0 | yes |
| 1000 | 1000/1000 | 5002 | 10.5 | 11.2 | 23.2 | 0 | 0 | 0 | 5.64 | 16113 | 4412903 | 1058 | 2 | 1 | 5.76 | 10.0 | 4.12 | 8.93 | 0 | yes |
| 2000 | 2000/2000 | 5350 | 357 | 77.7 | 413 | 0 | 0 | 0 | 12.9 | 32129 | 8818232 | 2182 | 4 | 3 | 5.73 | 8.87 | 48.3 | 454 | 0 | yes |
| 5000 | 5000/5000 | 14085 | 9070 | 6368 | 9030 | 0 | 0 | 0 | 34.4 | 80155 | 22035831 | 5930 | 4 | 5 | 5.68 | 8.90 | 3821 | 10133 | 0 | yes |
<!-- /case:reconnect -->

<!-- case:reconnect_burst -->
### Reconnect wave after a deploy, shared board, arriving in a burst

Run 2026-11-22 13:17 UTC on commit c4a007596, Apple M1 Pro, 10 cores, 16 GB, macOS 26.6.2, load average 2.39 when the run started, PostgreSQL 15.14 (Homebrew), synchronous_commit on, fsync on, wal_sync_method open_datasync, Elixir 1.20.0 on OTP 29.

- 2000 cards read with a bare `allow :read`, which lets every client read every card
- 100 writes made while the clients are away, each to a row of its own
- each client comes back at a random moment within 250 ms, greeting with its replica identity as a browser does
- 0 writes per second while they do, each to a row of its own
- anonymous clients, coming back with their places after a node restart, steps of 100, 500, 1000, 2000, 5000 clients
- a step stops, and the sweep with it, when the server node's memory passes 4 GB
- a step passes when every client is caught up within 120 s of the first one coming back, holding every write it should and no other, with none told to start over

Clients per node: **at least 5000**

#### Wave

| Clients | Caught up | Last caught up ms | After the last return ms | Own wait p50 ms | Own wait p99 ms | Return restarts | Heap kills | Sessions cut | Server CPU s | DB commits | DB rows scanned | DB ms | Peak sync backends | Peak other backends | App p50 ms before | App p99 ms before | App p50 ms during | App p99 ms during | App requests failed | Step passed |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 100 | 100/100 | 292 | 43.9 | 43.5 | 70.3 | 0 | 0 | 0 | 0.62 | 1682 | 445874 | 117 | 1 | 0 | 5.69 | 9.65 | 6.83 | 35.2 | 0 | yes |
| 500 | 500/500 | 1577 | 1326 | 978 | 1488 | 0 | 0 | 0 | 2.84 | 8083 | 2208198 | 521 | 4 | 1 | 6.49 | 11.0 | 6.28 | 339 | 0 | yes |
| 1000 | 1000/1000 | 3099 | 2844 | 2168 | 2952 | 0 | 0 | 0 | 5.49 | 16056 | 4411106 | 1040 | 3 | 5 | 6.38 | 10.6 | 6.42 | 1005 | 0 | yes |
| 2000 | 2000/2000 | 6153 | 5893 | 4199 | 5897 | 0 | 0 | 0 | 11.7 | 32129 | 8818927 | 2138 | 4 | 5 | 6.21 | 10.6 | 6.53 | 2010 | 0 | yes |
| 5000 | 5000/5000 | 16994 | 16716 | 11853 | 16643 | 0 | 0 | 0 | 32.1 | 80156 | 22036932 | 5820 | 4 | 6 | 5.95 | 10.1 | 7.81 | 6089 | 0 | yes |
<!-- /case:reconnect_burst -->

<!-- case:reconnect_writes -->
### Reconnect wave after a deploy, shared board, with writes during the wave

Run 2026-11-22 13:52 UTC on commit c4a007596, Apple M1 Pro, 10 cores, 16 GB, macOS 26.6.2, load average 2.37 when the run started, PostgreSQL 15.14 (Homebrew), synchronous_commit on, fsync on, wal_sync_method open_datasync, Elixir 1.20.0 on OTP 29.

- 20000 cards read with a bare `allow :read`, which lets every client read every card
- 4000 writes made while the clients are away, each to a row of its own
- each client comes back at a random moment within 5000 ms, greeting with its replica identity as a browser does
- 20 writes per second while they do, each to a row of its own
- anonymous clients, coming back with their places after a node restart, steps of 100, 500 clients
- a step stops, and the sweep with it, when the server node's memory passes 4 GB
- a step passes when every client is caught up within 40 s of the first one coming back, holding every write it should and no other, with none told to start over

Clients per node: **at least 500**

#### Wave

| Clients | Caught up | Last caught up ms | After the last return ms | Own wait p50 ms | Own wait p99 ms | Return restarts | Heap kills | Sessions cut | Server CPU s | DB commits | DB rows scanned | DB ms | Peak sync backends | Peak other backends | App p50 ms before | App p99 ms before | App p50 ms during | App p99 ms during | App requests failed | Step passed |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 100 | 100/100 | 5165 | 193 | 172 | 248 | 0 | 0 | 0 | 14.1 | 4092 | 10579468 | 2426 | 3 | 1 | 6.72 | 11.6 | 5.15 | 10.9 | 0 | yes |
| 500 | 500/500 | 22567 | 17586 | 8435 | 17417 | 0 | 0 | 0 | 85.6 | 19163 | 55698192 | 12805 | 3 | 2 | 6.97 | 12.3 | 6.21 | 17.2 | 0 | yes |

#### Returning sessions

| Clients | Writes during the wave | Most waiting | KB waiting, most in one | KB catching up, most in one | MB catching up, most at once | Longest mailbox | Gate reads missed | Turns seen | Turn p50 ms | Turn max ms |
|---|---|---|---|---|---|---|---|---|---|---|
| 100 | 106 | 2 | 3.31 | 10870 | 34.3 | 6 | 0 | 100 | 162 | 192 |
| 500 | 457 | 376 | 27.6 | 11413 | 36.1 | 6 | 0 | 500 | 173 | 233 |
<!-- /case:reconnect_writes -->

<!-- case:reconnect_tenants -->
### Reconnect wave after a deploy, multi-tenant app

Run 2026-11-22 13:39 UTC on commit c4a007596, Apple M1 Pro, 10 cores, 16 GB, macOS 26.6.2, load average 2.41 when the run started, PostgreSQL 15.14 (Homebrew), synchronous_commit on, fsync on, wal_sync_method open_datasync, Elixir 1.20.0 on OTP 29.

- 400 tenants of 5 members with 100 tasks each, 40000 tasks in all, read with `allow :read, when: any(member <- tenant.members, member.user_id == user_id())`
- 100 writes made while the clients are away, each to a row of its own
- each client comes back at a random moment within 5000 ms, greeting with its replica identity as a browser does
- 0 writes per second while they do, each to a row of its own
- signed-in clients, one per user, filling whole tenants in order, coming back with their places after a node restart, steps of 100, 500, 1000, 2000 clients
- a step stops, and the sweep with it, when the server node's memory passes 4 GB
- a step passes when every client is caught up within 120 s of the first one coming back, holding every write it should and no other, with none told to start over

Clients per node: **at least 2000**

#### Wave

| Clients | Caught up | Last caught up ms | After the last return ms | Own wait p50 ms | Own wait p99 ms | Return restarts | Heap kills | Sessions cut | Server CPU s | DB commits | DB rows scanned | DB ms | Peak sync backends | Peak other backends | App p50 ms before | App p99 ms before | App p50 ms during | App p99 ms during | App requests failed | Step passed |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 100 | 100/100 | 4982 | 28.9 | 28.9 | 48.9 | 0 | 0 | 0 | 0.25 | 1714 | 8130528 | 2203 | 3 | 1 | 6.67 | 11.3 | 3.51 | 7.29 | 0 | yes |
| 500 | 500/500 | 6869 | 1876 | 830 | 1861 | 0 | 0 | 0 | 1.72 | 8051 | 40615128 | 24310 | 4 | 1 | 6.17 | 10.8 | 3.56 | 8.38 | 0 | yes |
| 1000 | 1000/1000 | 13589 | 8626 | 4459 | 8535 | 0 | 0 | 0 | 3.39 | 15919 | 81221474 | 48054 | 4 | 1 | 5.95 | 17.3 | 3.34 | 7.87 | 0 | yes |
| 2000 | 2000/2000 | 27250 | 22250 | 11147 | 22043 | 0 | 0 | 0 | 6.81 | 32019 | 162429459 | 96150 | 4 | 1 | 5.68 | 8.57 | 3.44 | 9.17 | 0 | yes |
<!-- /case:reconnect_tenants -->

<!-- case:reconnect_tenants_burst -->
### Reconnect wave after a deploy, multi-tenant app, arriving in a burst

Run 2026-11-22 13:45 UTC on commit c4a007596, Apple M1 Pro, 10 cores, 16 GB, macOS 26.6.2, load average 2.25 when the run started, PostgreSQL 15.14 (Homebrew), synchronous_commit on, fsync on, wal_sync_method open_datasync, Elixir 1.20.0 on OTP 29.

- 400 tenants of 5 members with 100 tasks each, 40000 tasks in all, read with `allow :read, when: any(member <- tenant.members, member.user_id == user_id())`
- 100 writes made while the clients are away, each to a row of its own
- each client comes back at a random moment within 250 ms, greeting with its replica identity as a browser does
- 0 writes per second while they do, each to a row of its own
- signed-in clients, one per user, filling whole tenants in order, coming back with their places after a node restart, steps of 100, 500, 1000, 2000 clients
- a step stops, and the sweep with it, when the server node's memory passes 4 GB
- a step passes when every client is caught up within 120 s of the first one coming back, holding every write it should and no other, with none told to start over

Clients per node: **at least 2000**

#### Wave

| Clients | Caught up | Last caught up ms | After the last return ms | Own wait p50 ms | Own wait p99 ms | Return restarts | Heap kills | Sessions cut | Server CPU s | DB commits | DB rows scanned | DB ms | Peak sync backends | Peak other backends | App p50 ms before | App p99 ms before | App p50 ms during | App p99 ms during | App requests failed | Step passed |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 100 | 100/100 | 1465 | 1218 | 672 | 1221 | 0 | 0 | 0 | 0.36 | 1618 | 8130960 | 5041 | 4 | 1 | 5.91 | 8.56 | 3.76 | 11.5 | 0 | yes |
| 500 | 500/500 | 7906 | 7654 | 4184 | 7606 | 0 | 0 | 0 | 1.69 | 8158 | 40615668 | 25943 | 4 | 2 | 6.39 | 11.0 | 3.91 | 293 | 0 | yes |
| 1000 | 1000/1000 | 15690 | 15437 | 8381 | 15541 | 0 | 0 | 0 | 3.36 | 15931 | 81219052 | 51459 | 4 | 1 | 5.68 | 8.72 | 3.38 | 834 | 0 | yes |
| 2000 | 2000/2000 | 31268 | 31006 | 16770 | 30789 | 0 | 0 | 0 | 7.01 | 31980 | 162430323 | 102501 | 4 | 1 | 5.87 | 9.07 | 3.40 | 1779 | 0 | yes |
<!-- /case:reconnect_tenants_burst -->

<!-- case:catchups -->
### How many catch-ups a node runs at once

Run 2026-11-22 13:25 UTC on commit c4a007596, Apple M1 Pro, 10 cores, 16 GB, macOS 26.6.2, load average 2.95 when the run started, PostgreSQL 15.14 (Homebrew), synchronous_commit on, fsync on, wal_sync_method open_datasync, Elixir 1.20.0 on OTP 29.

- 2000 cards read with a bare `allow :read`, which lets every client read every card
- 100 writes made while the clients are away, each to a row of its own
- each client comes back at a random moment within 5000 ms, greeting with its replica identity as a browser does
- 0 writes per second while they do, each to a row of its own
- 1000 anonymous clients
- the same wave at 1, 2, 4, 8, 16 catch-ups at once, with sync's database pool the same size, each on a fresh log and fresh nodes
- a wave passes when every client is caught up within 120 s of the first one coming back, holding every write it should and no other

Queue cleared after the last client came back: **1.61 s at 1, 0.01 s at 2, 0.02 s at 4, 0.01 s at 8, 0.01 s at 16**

#### Per number of catch-ups at once

| Catch-ups at once | Caught up | Last caught up ms | After the last return ms | Return restarts | Own wait p50 ms | Own wait p99 ms | Server CPU s | DB ms | Peak sync backends | App p50 ms during | App p99 ms during | App requests failed | Step passed | Why not |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 1000/1000 | 6583 | 1608 | 0 | 874 | 1576 | 5.05 | 1022 | 1 | 3.98 | 8.00 | 0 | yes | - |
| 2 | 1000/1000 | 5001 | 10.0 | 0 | 12.0 | 61.7 | 5.56 | 1035 | 2 | 4.49 | 14.3 | 0 | yes | - |
| 4 | 1000/1000 | 4991 | 15.4 | 0 | 11.3 | 34.6 | 5.69 | 1045 | 2 | 4.36 | 15.7 | 0 | yes | - |
| 8 | 1000/1000 | 4994 | 12.4 | 0 | 11.2 | 18.3 | 5.74 | 1066 | 2 | 4.50 | 8.88 | 0 | yes | - |
| 16 | 1000/1000 | 4986 | 10.5 | 0 | 11.3 | 23.4 | 5.69 | 1078 | 3 | 4.32 | 10.4 | 0 | yes | - |
<!-- /case:catchups -->

<!-- case:catchups_burst -->
### How many catch-ups a node runs at once, arriving in a burst

Run 2026-11-22 14:33 UTC on commit eb20796a4, Apple M1 Pro, 10 cores, 16 GB, macOS 26.6.2, load average 2.29 when the run started, PostgreSQL 15.14 (Homebrew), synchronous_commit on, fsync on, wal_sync_method open_datasync, Elixir 1.20.0 on OTP 29.

- 2000 cards read with a bare `allow :read`, which lets every client read every card
- 100 writes made while the clients are away, each to a row of its own
- each client comes back at a random moment within 250 ms, greeting with its replica identity as a browser does
- 0 writes per second while they do, each to a row of its own
- 1000 anonymous clients
- the same wave at 1, 2, 3, 4, 5, 6, 7, 8, 16 catch-ups at once, with sync's database pool the same size, each on a fresh log and fresh nodes
- a wave passes when every client is caught up within 120 s of the first one coming back, holding every write it should and no other

Queue cleared after the last client came back: **7.56 s at 1, 4.40 s at 2, 3.44 s at 3, 2.91 s at 4, 2.61 s at 5, 2.41 s at 6, 2.24 s at 7, 2.14 s at 8, 1.96 s at 16**

#### Per number of catch-ups at once

| Catch-ups at once | Caught up | Last caught up ms | After the last return ms | Return restarts | Own wait p50 ms | Own wait p99 ms | Server CPU s | DB ms | Peak sync backends | App p50 ms during | App p99 ms during | App requests failed | Step passed | Why not |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 1000/1000 | 7810 | 7557 | 0 | 4431 | 7725 | 4.79 | 987 | 1 | 3.57 | 964 | 0 | yes | - |
| 2 | 1000/1000 | 4659 | 4404 | 0 | 2926 | 4516 | 5.27 | 984 | 2 | 4.77 | 988 | 0 | yes | - |
| 3 | 1000/1000 | 3687 | 3436 | 0 | 2341 | 3638 | 5.60 | 1023 | 2 | 5.37 | 1002 | 0 | yes | - |
| 4 | 1000/1000 | 3162 | 2908 | 0 | 2184 | 3052 | 5.68 | 1037 | 3 | 6.04 | 1006 | 0 | yes | - |
| 5 | 1000/1000 | 2870 | 2614 | 0 | 2073 | 2737 | 5.77 | 1046 | 3 | 7.93 | 1015 | 0 | yes | - |
| 6 | 1000/1000 | 2670 | 2414 | 0 | 1884 | 2576 | 5.90 | 1070 | 4 | 9.68 | 1017 | 0 | yes | - |
| 7 | 1000/1000 | 2495 | 2241 | 0 | 1877 | 2354 | 6.01 | 1092 | 4 | 15.9 | 991 | 0 | yes | - |
| 8 | 1000/1000 | 2398 | 2143 | 0 | 1829 | 2257 | 6.04 | 1109 | 5 | 45.2 | 1009 | 0 | yes | - |
| 16 | 1000/1000 | 2209 | 1956 | 0 | 1683 | 2091 | 8.31 | 1239 | 9 | 168 | 1013 | 0 | yes | - |
<!-- /case:catchups_burst -->

<!-- case:session_memory -->
### Memory per connected session

Run 2026-11-22 13:06 UTC on commit c4a007596, Apple M1 Pro, 10 cores, 16 GB, macOS 26.6.2, load average 1.56 when the run started, PostgreSQL 15.14 (Homebrew), synchronous_commit on, fsync on, wal_sync_method open_datasync, Elixir 1.20.0 on OTP 29.

- cards read with a bare `allow :read`, so every client holds every card, 1000, 10000, 100000 of them, each seeded on its own
- 10 anonymous clients, 3 from 100000 rows up, each connecting once the one before it is filled, sitting idle when read
- a build with no permission checks in the browser, so rows carry no verdicts. With them, a first arrival also keeps a verdict entry per row, and a returning session doesn't
- a run stops when the server node's memory passes 4 GB

Memory per session: **1579 KB as it sits idle, 1567 KB after collection, for 100000 rows, 16.0 off-heap binary bytes per row**

#### Per session, median

| Rows | Clients | First arrival KB | After collection KB | Of which off-heap binaries KB | Rest KB | Off-heap binary bytes per row | Returning KB | Returning after collection KB | Returning off-heap binary bytes per row | Returning, back to caught up ms | Reading its ids ms | Stream KB |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1000 | 10 | 29.7 | 19.7 | 15.7 | 4.04 | 16.0 | 20.4 | 19.7 | 16.1 | 11.9 | 3.95 | 370 |
| 10000 | 10 | 170 | 160 | 156 | 4.04 | 16.0 | 161 | 160 | 16.0 | 14.2 | 3.76 | 31.2 |
| 100000 | 3 | 1579 | 1567 | 1563 | 4.04 | 16.0 | 1567 | 1567 | 16.0 | 43.8 | 38.7 | 31.2 |
<!-- /case:session_memory -->

<!-- case:backlog -->
### A long transaction holding up the dispatcher

Run 2026-11-22 13:57 UTC on commit c4a007596, Apple M1 Pro, 10 cores, 16 GB, macOS 26.6.2, load average 3.00 when the run started, PostgreSQL 15.14 (Homebrew), synchronous_commit on, fsync on, wal_sync_method open_datasync, Elixir 1.20.0 on OTP 29.

- 2000 cards read with a bare `allow :read`, 100 anonymous clients connected
- 8 writers commit batches of 10 effects for 1000 replicas while one transaction holds the dispatcher up
- each size runs on a fresh log and a fresh server node, on a Postgres server of its own
- a delivery is waited on for at most 120 s, and a dash means it didn't reach every client in that time, or a client lost its stream first
- a run stops when the server node's memory passes 4 GB

Read of the batches above a delivered one: **99.2 ms with 300001 log rows above it, naming 1000 replicas, 83.9 KB copied to each session**

#### Per backlog size

| Log rows above | Replicas named | Clients | Read ms, direct | List KB | List MB across sessions | Ordinary write ms | Held-up write ms | Memory rise MB | Whole backlog ms | Backlog memory rise MB | Streams lost | Heap kills | Sessions cut | Dispatcher restarted |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 30001 | 1000 | 100 | 11.1 | 83.9 | 8.19 | 3.36 | 15.1 | 0.83 | 684 | 661 | 0 | 0 | 0 | no |
| 300001 | 1000 | 100 | 99.2 | 83.9 | 8.19 | 3.69 | 105 | 9.10 | 3532 | 1165 | 0 | 0 | 0 | no |
<!-- /case:backlog -->

<!-- case:big_set -->
### One write touching a row with a big set

Run 2026-11-22 14:04 UTC on commit c4a007596, Apple M1 Pro, 10 cores, 16 GB, macOS 26.6.2, load average 3.69 when the run started, PostgreSQL 15.14 (Homebrew), synchronous_commit on, fsync on, wal_sync_method open_datasync, Elixir 1.20.0 on OTP 29.

- one tag with a set of hidden posts, plus 7 posts its 100 anonymous clients may read, so they hold the tag and those few
- each size is seeded on its own and runs on a fresh server node
- 3 ordinary writes to a post outside the set, then 3 writes linking a post into it, each waited on for at most 120 s, and a dash means none reached every client in that time, or a client lost its stream first
- then the tag is hidden from every client and shown again, which has each session scan the whole set
- a run stops when the server node's memory passes 4 GB

A write into the set: **14.8 ms to the last client with 30000 posts in the set, against 3.72 ms for a write outside it (300000 posts stopped at the 4 GB memory limit)**

#### Per set size

| Posts in the set | Clients | Read of the set ms, direct | Set MB | Write outside it ms | Write into it ms | Memory rise MB | Tag dropped ms | Tag handed back ms | Drop and hand back memory rise MB | Streams lost | Heap kills | Sessions cut |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 30000 | 100 | 13.4 | 0.92 | 3.72 | 14.8 | 3.07 | 1933 | 3721 | 1725 | 0 | 0 | 0 |
<!-- /case:big_set -->

<!-- case:lock -->
### The pg_notify commit lock

Run 2026-11-15 16:25 UTC on commit d1837e12f, Apple M1 Pro, 10 cores, 16 GB, macOS 26.6.2, load average 9.95 when the run started, PostgreSQL 15.14 (Homebrew), synchronous_commit on, fsync on, wal_sync_method open_datasync, Elixir 1.20.0 on OTP 29.

- 1, 2, 4, 8, 16 and 32 writers at once, for 10 s each
- plain and notify writers run on connections of the driver's own, into a scratch table, notify with one connection listening; Hologram's run on the server node, with a pool of 37 connections at every writer count, the most writers plus 5, and no client connected
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
