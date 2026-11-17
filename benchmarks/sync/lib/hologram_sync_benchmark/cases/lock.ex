defmodule HologramSyncBenchmark.Cases.Lock do
  @moduledoc false

  # credo:disable-for-this-file Credo.Check.Refactor.IoPuts

  # Whether the lock Postgres takes when a transaction that called pg_notify commits caps how
  # many writes per second get through. PreCommit_Notify takes one lock for the whole server, on
  # the database object with no database (`pg_locks`: locktype object, classid 1262, objid 0), so
  # those commits happen one at a time, whatever database they're in and however many cores
  # there are.
  #
  # Three kinds of writer, each run with 1, 2, 4 ... writers at once for a fixed time:
  #
  # - plain: a transaction inserting one row, on connections of the driver's own,
  # - notify: the same plus `SELECT pg_notify(...)`, with one connection listening,
  # - Hologram: `DB.update!` on the server node, each writer on cards of its own so row locks
  #   don't serialize them, which notifies the nodes in every transaction as an app's writes do.
  #
  # A sampler reads the lock from pg_locks throughout: whether someone holds it, how many wait for
  # it, and whether a holder is in another database. A lock held nearly all the time caps the
  # writers: it can pass only a few percent more. The rate over the held share is then the most
  # commits of that kind it lets through, which depends on how long each holds it.

  alias Hologram.DB.Config
  alias HologramSyncBenchmark.DB
  alias HologramSyncBenchmark.Entities.Card
  alias HologramSyncBenchmark.Peer
  alias HologramSyncBenchmark.Report
  alias HologramSyncBenchmark.Seeding
  alias HologramSyncBenchmark.Writer

  # The share of samples the lock must be held in for it to count as the cap. Below it, the rate
  # over the held share is an extrapolation: how long a commit holds the lock changes with load.
  @busy_share 0.9

  @channel "bench_lock"

  # Connections the case needs besides its writers: the driver's, the sampler's, the listener,
  # and the server node's own use of its pool.
  @connections_besides_writers 12

  @sample_ms 50

  @table "bench_lock"

  @writers [1, 2, 4, 8, 16, 32]

  @doc """
  Runs the lock case with the given options, writes its section into the README, and returns
  :ok.
  """
  @spec run(pid, keyword) :: :ok
  def run(conn, opts) do
    counts = opts[:clients] || @writers
    duration_ms = opts[:lock_duration] * 1_000

    :ok = check_connections!(conn, Enum.max(counts))
    :ok = Report.check_readme!()
    run_line = Report.run_line(conn)

    create_table!(conn)

    try do
      plain = Enum.map(counts, &driver_writes(conn, &1, duration_ms, false))
      notify = Enum.map(counts, &driver_writes(conn, &1, duration_ms, true))
      hologram = hologram_writes(conn, counts, duration_ms)

      rows = Enum.zip_with([counts, plain, notify, hologram], &row/1)
      verdict = verdict(notify, hologram)

      IO.puts(verdict)

      Report.write_case!(
        "lock",
        "The pg_notify commit lock",
        run_line,
        options(opts, counts),
        verdict,
        [{"Writes per second by writers at once", columns(), rows}],
        figure_label: "Verdict"
      )
    after
      drop_table(conn)
    end
  end

  @doc """
  Runs the given number of writers on the given cards for the given time, each updating cards
  of its own in turn, and returns how many writes went through and the milliseconds until the
  last of them finished. Runs on the server node.
  """
  @spec write_cards(tuple, pos_integer, pos_integer) :: {non_neg_integer, float}
  def write_cards(ids, count, duration_ms) do
    timed(fn ->
      deadline = System.monotonic_time(:millisecond) + duration_ms

      0..(count - 1)
      |> Task.async_stream(&write_cards_until(ids, &1, count, deadline, 0),
        max_concurrency: count,
        timeout: :infinity
      )
      |> Enum.sum_by(fn {:ok, writes} -> writes end)
    end)
  end

  # Writers, the sampler, the listener and the server node's pool all hold connections, and
  # Postgres refuses past max_connections, counted over every database on the server.
  defp check_connections!(conn, writers) do
    %{rows: [[max, reserved, open]]} =
      Postgrex.query!(
        conn,
        """
        SELECT current_setting('max_connections')::int,
               current_setting('superuser_reserved_connections')::int,
               (SELECT count(*) FROM pg_stat_activity WHERE backend_type = 'client backend')::int
        """,
        []
      )

    needed = writers + @connections_besides_writers
    free = max - reserved - open

    if needed > free do
      raise "#{writers} writers need about #{needed} connections, Postgres has #{free} free"
    end

    :ok
  end

  defp columns do
    [
      "Writers",
      "Plain commits/s",
      "Notify commits/s",
      "Notify lock held",
      "Notify writers queued",
      "Hologram writes/s",
      "Hologram lock held",
      "Hologram writers queued",
      "Other databases holding it"
    ]
  end

  defp create_table!(conn) do
    drop_table(conn)

    # Autovacuum off, as on the benchmark's other tables: its work would land in the window.
    Postgrex.query!(
      conn,
      "CREATE TABLE #{@table} (id bigserial PRIMARY KEY, v bigint) " <>
        "WITH (autovacuum_enabled = false)",
      []
    )
  end

  # Never raises: a cleanup that fails, like one on a connection that's gone, mustn't hide the
  # error that ended the run. A table left behind is dropped at the next start.
  defp drop_table(conn) do
    Postgrex.query(conn, "DROP TABLE IF EXISTS #{@table}", [])
  catch
    _kind, _reason -> :error
  end

  # Each writer on a connection of its own, looping until the time is up. Notify writers also
  # hold one connection listening, as a node does.
  defp driver_writes(conn, count, duration_ms, notify?) do
    :ok = DB.vacuum_analyze!(conn)

    opts = Keyword.merge(Config.connection_opts(), backoff_type: :stop, sync_connect: true)
    listener = if notify?, do: listen(opts)

    connections =
      for _index <- 1..count do
        {:ok, connection} = Postgrex.start_link(opts)
        connection
      end

    {{commits, elapsed_ms}, lock} =
      with_sampler(fn -> timed(fn -> write_all(connections, duration_ms, notify?) end) end)

    Enum.each(connections, &GenServer.stop/1)
    if listener, do: stop_listener(listener)

    result = %{lock: lock, per_second: commits * 1_000 / elapsed_ms, writers: count}
    IO.puts("  #{if notify?, do: "notify", else: "plain"}, #{count} writers: #{summary(result)}")

    result
  end

  defp write_all(connections, duration_ms, notify?) do
    deadline = System.monotonic_time(:millisecond) + duration_ms

    connections
    |> Task.async_stream(&write_until(&1, deadline, notify?),
      max_concurrency: length(connections),
      timeout: :infinity
    )
    |> Enum.sum_by(fn {:ok, commits} -> commits end)
  end

  defp hologram_writes(conn, counts, duration_ms) do
    max_writers = Enum.max(counts)

    {_seeding, nil} = Seeding.board!(conn, Card, max_writers * 10)

    # One size for every writer count: the most writers need a connection each, on top of what
    # the node uses itself.
    database = Application.get_env(:hologram, :database, [])

    Application.put_env(
      :hologram,
      :database,
      Keyword.put(database, :pool_size, pool_size(counts))
    )

    try do
      Enum.map(counts, &hologram_step(conn, &1, duration_ms))
    after
      Application.put_env(:hologram, :database, database)
    end
  end

  defp hologram_step(conn, count, duration_ms) do
    :ok = DB.vacuum_analyze!(conn)
    autovacuum_before = DB.autovacuum_runs(conn)

    Peer.with_peer(fn peer ->
      ids = Peer.rpc(peer, Writer, :ids, [Card])

      {{writes, elapsed_ms}, lock} =
        with_sampler(fn ->
          Peer.rpc(peer, __MODULE__, :write_cards, [ids, count, duration_ms])
        end)

      result = %{
        autovacuum_ran: DB.autovacuum_runs(conn) != autovacuum_before,
        lock: lock,
        per_second: writes * 1_000 / elapsed_ms,
        writers: count
      }

      IO.puts("  Hologram, #{count} writers: #{summary(result)}")

      result
    end)
  end

  # From a process that drains what it's sent, as a node's listener does: notifications delivered
  # to a process that never reads them would pile up in its mailbox.
  defp listen(opts) do
    owner = self()

    listener =
      spawn_link(fn ->
        {:ok, notifications} = Postgrex.Notifications.start_link(opts)
        {:ok, _ref} = Postgrex.Notifications.listen(notifications, @channel)
        send(owner, {:listening, self()})
        drain(owner)
      end)

    receive do
      {:listening, ^listener} -> listener
    end
  end

  defp drain(owner) do
    receive do
      {:stop, ^owner} -> :ok
      _notification -> drain(owner)
    end
  end

  defp stop_listener(listener) do
    ref = Process.monitor(listener)
    send(listener, {:stop, self()})

    receive do
      {:DOWN, ^ref, :process, ^listener, _reason} -> :ok
    end
  end

  defp options(opts, counts) do
    [
      "#{format_counts(counts)} #{if counts == [1], do: "writer", else: "writers"} at once, " <>
        "for #{opts[:lock_duration]} s each",
      "plain and notify writers run on connections of the driver's own, into a scratch table, " <>
        "notify with one connection listening; Hologram's run on the server node, with a pool " <>
        "of #{pool_size(counts)} connections at every writer count, the most writers plus 5, " <>
        "and no client connected",
      "the lock is one for the whole server; \"held\" is the share of samples, every " <>
        "#{@sample_ms} ms, it was held in, \"queued\" the writers waiting for it on average, " <>
        "as a share of all writers, and \"other databases\" the share of samples a holder was in " <>
        "another database, which measures what else on the server notifies",
      "a notifying commit costs more than a plain one even with one writer, where nothing " <>
        "queues, so only the growth past the 1-writer row can be the lock"
    ]
  end

  defp format_counts([count]), do: "#{count}"

  defp format_counts(counts) do
    {most, [last]} = Enum.split(counts, -1)
    "#{Enum.join(most, ", ")} and #{last}"
  end

  defp pool_size(counts), do: Enum.max(counts) + 5

  defp percent(nil), do: nil

  defp percent(share), do: "#{round(share * 100)}%"

  defp queued_share(%{lock: lock, writers: writers}), do: lock.queued / writers

  defp row([count, plain, notify, hologram]) do
    [
      count,
      plain.per_second,
      notify.per_second,
      percent(notify.lock.held),
      percent(queued_share(notify)),
      hologram.per_second,
      percent(hologram.lock.held) <> if(hologram.autovacuum_ran, do: ", autovacuum ran", else: ""),
      percent(queued_share(hologram)),
      percent(max(notify.lock.foreign, hologram.lock.foreign))
    ]
  end

  # One sample of the server-wide notify lock: whether it's held, how many of the benchmark's
  # backends wait for it, and whether its holder is in another database.
  defp sample_lock(conn) do
    %{rows: [[held, waiting, foreign]]} =
      Postgrex.query!(
        conn,
        """
        SELECT
          count(*) FILTER (WHERE l.granted)::int,
          count(*) FILTER (WHERE NOT l.granted AND a.datname = current_database())::int,
          count(*) FILTER (WHERE l.granted AND a.datname IS DISTINCT FROM current_database())::int
        FROM pg_locks l
        LEFT JOIN pg_stat_activity a ON a.pid = l.pid
        WHERE l.locktype = 'object' AND l.classid = 1262 AND l.objid = 0
        """,
        []
      )

    %{foreign: min(foreign, 1), held: min(held, 1), queued: waiting, samples: 1}
  end

  defp sample(owner, conn, totals) do
    receive do
      {:stop, ^owner} ->
        GenServer.stop(conn)
        send(owner, {:lock, self(), totals})
    after
      @sample_ms ->
        now = sample_lock(conn)

        sample(owner, conn, Map.merge(totals, now, fn _key, total, value -> total + value end))
    end
  end

  defp summary(result) do
    "#{round(result.per_second)} commits/s, lock held #{percent(result.lock.held)}, " <>
      "#{percent(queued_share(result))} of writers queued" <>
      if(result.lock.foreign > 0, do: ", OTHER DATABASES HELD IT", else: "") <>
      if(result[:autovacuum_ran], do: ", AUTOVACUUM RAN", else: "")
  end

  # A sampler on a connection of its own, reading the lock while the given function runs, then
  # the shares of samples it was held in and held by another database, and the writers waiting
  # for it on average. The function starts once the sampler is connected, so its first writes are
  # sampled too, and a run with no samples raises, since its shares would read as a lock never
  # held.
  defp with_sampler(fun) do
    owner = self()
    totals = %{foreign: 0, held: 0, queued: 0, samples: 0}

    sampler =
      spawn_link(fn ->
        conn = DB.connect!()
        send(owner, {:sampling, self()})
        sample(owner, conn, totals)
      end)

    receive do
      {:sampling, ^sampler} -> :ok
    end

    result = fun.()
    send(sampler, {:stop, owner})

    receive do
      {:lock, ^sampler, %{samples: 0}} ->
        raise "the lock was never sampled, so a run needs more than #{@sample_ms} ms"

      {:lock, ^sampler, totals} ->
        lock = %{
          foreign: totals.foreign / totals.samples,
          held: totals.held / totals.samples,
          queued: totals.queued / totals.samples
        }

        {result, lock}
    end
  end

  # The lock caps a kind of writer when some writer count held it nearly all the time, since it can
  # then pass only a few percent more. The ceiling is the highest rate over held share among those
  # counts: at full hold, how many of these commits the lock lets through.
  defp verdict(notify, hologram) do
    kinds = [{"notifying commits", notify}, {"Hologram's writes", hologram}]

    Enum.map_join(kinds, " ", fn {name, results} -> verdict_line(name, results) end)
  end

  defp verdict_line(name, results) do
    peak = Enum.max_by(results, & &1.per_second)
    saturated = Enum.filter(results, &(&1.lock.held >= @busy_share))

    peak_text =
      "#{String.capitalize(name)} peak at #{round(peak.per_second)} per second, with " <>
        "#{peak.writers} writers and the lock held #{percent(peak.lock.held)} of the time."

    case saturated do
      [] ->
        held = Enum.max_by(results, & &1.lock.held).lock.held

        peak_text <>
          " The lock was held at most #{percent(held)} of the time, so it doesn't cap them."

      saturated ->
        # Never below the peak: a rate measured is one the lock let through.
        ceiling =
          saturated
          |> Enum.map(&(&1.per_second / &1.lock.held))
          |> Enum.max()
          |> max(peak.per_second)

        writers = Enum.map(saturated, & &1.writers)

        peak_text <>
          " With #{format_counts(writers)} writers the lock was held nearly all the time, so " <>
          "it caps them, at about #{round(ceiling)} per second."
    end
  end

  defp write_cards_until(ids, writer, count, deadline, writes) do
    if System.monotonic_time(:millisecond) >= deadline do
      writes
    else
      # Each writer keeps to the cards whose position is its own mod the writer count, so no two
      # writers update one row and row locks never serialize them.
      index = writer + count * rem(writes, div(tuple_size(ids), count))
      Writer.update(Card, elem(ids, index), :title, "lock #{writes}")

      write_cards_until(ids, writer, count, deadline, writes + 1)
    end
  end

  # The given function's result and the milliseconds it took. Writers check the deadline before a
  # write, so the last writes finish past it, and a rate over the set duration would count them
  # in less time than they took.
  defp timed(fun) do
    started_at = System.monotonic_time(:microsecond)
    result = fun.()

    {result, (System.monotonic_time(:microsecond) - started_at) / 1_000}
  end

  defp write_until(conn, deadline, notify?, commits \\ 0) do
    if System.monotonic_time(:millisecond) >= deadline do
      commits
    else
      {:ok, _result} = Postgrex.transaction(conn, &write_row(&1, commits, notify?))

      write_until(conn, deadline, notify?, commits + 1)
    end
  end

  defp write_row(transaction, value, notify?) do
    Postgrex.query!(transaction, "INSERT INTO #{@table} (v) VALUES ($1)", [value])

    if notify?, do: Postgrex.query!(transaction, "SELECT pg_notify($1, '')", [@channel])
  end
end
