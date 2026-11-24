defmodule HologramSyncBenchmark.DB do
  @moduledoc false

  # The driver's own view of the database: resetting it between cases and steps, and reading the
  # counters Postgres keeps, over connections of the driver's own. Nothing here goes through the
  # server node, so none of it shows in the server's figures.

  alias Hologram.DB.Config
  alias Hologram.DB.Mapper

  # Postgres flushes a backend's counters to the shared statistics lazily, at most once a second
  # while it's busy and up to 10 s after it goes idle. Reading 11 s after a phase ends catches
  # every pooled backend's share of it.
  @settle_ms 11_000

  # The 10 s idle flush the settle relies on arrived with PG 15's shared-memory statistics. On
  # PG 14 an idle backend keeps its counts until its next transaction, so a read can miss them.
  @min_server_version 150_000

  @backend_sample_ms 200

  # What sync's own database pool names its connections (see Hologram.Sync.Pool).
  @sync_application_name "hologram_sync"

  # Hologram's own tables a case's runs fill: the log and the record of browser batches.
  @log_tables ["oplog", "mutation"]

  @type stats :: %{
          active_ms: float,
          at_ms: integer,
          tup_fetched: non_neg_integer,
          tup_returned: non_neg_integer,
          xact_commit: non_neg_integer
        }

  @doc """
  Opens a connection to the benchmark's database and returns it, refusing a server older than
  PG 15.
  """
  @spec connect! :: pid
  def connect! do
    {:ok, conn} =
      Config.connection_opts()
      |> Keyword.merge(backoff_type: :stop, sync_connect: true)
      |> Postgrex.start_link()

    %{rows: [[version]]} = Postgrex.query!(conn, "SHOW server_version_num", [])

    if String.to_integer(version) < @min_server_version do
      raise "the benchmark needs PostgreSQL 15 or newer, the server is #{version}"
    end

    conn
  end

  @doc """
  Returns how many times autovacuum has vacuumed or analyzed the benchmark's tables so far, for
  a step to check that it didn't run while being measured.
  """
  @spec autovacuum_runs(pid) :: non_neg_integer
  def autovacuum_runs(conn) do
    %{rows: [[runs]]} =
      Postgrex.query!(
        conn,
        """
        SELECT coalesce(sum(autovacuum_count + autoanalyze_count), 0)::bigint
        FROM pg_stat_user_tables
        WHERE schemaname = $1 OR (schemaname = $2 AND relname = ANY($3))
        """,
        [Mapper.data_schema(), Mapper.system_schema(), @log_tables]
      )

    runs
  end

  @doc """
  Starts counting the backends running a statement in the benchmark's database, every 200 ms on a
  connection of its own, and returns the sampler, for `stop_backend_sampler/1`.

  Not linked, so a sampler that fails doesn't take the driver and the sweep's unwritten results
  with it. It goes when the caller does.
  """
  @spec start_backend_sampler :: pid
  def start_backend_sampler do
    caller = self()

    spawn(fn ->
      caller_ref = Process.monitor(caller)

      {:ok, conn} =
        Config.connection_opts()
        |> Keyword.merge(backoff_type: :stop, sync_connect: true)
        |> Postgrex.start_link()

      sample_backends(conn, caller_ref, %{other: 0, sync: 0})
    end)
  end

  @doc """
  Stops the given sampler and returns the most backends it saw running a statement at once, those
  of sync's own pool and the rest apart. A lower bound: a statement shorter than the time between
  two samples can be missed. Both are nil for a sampler that failed, since a figure it couldn't
  read is no reason to lose the rest of a sweep's.
  """
  @spec stop_backend_sampler(pid) :: %{
          other: non_neg_integer | nil,
          sync: non_neg_integer | nil
        }
  def stop_backend_sampler(sampler) do
    ref = Process.monitor(sampler)
    send(sampler, {:stop, self(), ref})

    receive do
      {^ref, peak} ->
        Process.demonitor(ref, [:flush])
        peak

      {:DOWN, ^ref, :process, ^sampler, _reason} ->
        %{other: nil, sync: nil}
    end
  end

  defp sample_backends(conn, caller_ref, peak) do
    receive do
      {:stop, from, ref} ->
        GenServer.stop(conn)
        send(from, {ref, peak})

      {:DOWN, ^caller_ref, :process, _caller, _reason} ->
        GenServer.stop(conn)
    after
      @backend_sample_ms ->
        %{rows: [[sync, other]]} =
          Postgrex.query!(
            conn,
            """
            SELECT count(*) FILTER (WHERE application_name = $1),
                   count(*) FILTER (WHERE application_name <> $1)
            FROM pg_stat_activity
            WHERE datname = current_database() AND state = 'active' AND pid <> pg_backend_pid()
            """,
            [@sync_application_name]
          )

        peak = %{other: max(peak.other, other), sync: max(peak.sync, sync)}

        sample_backends(conn, caller_ref, peak)
    end
  end

  @doc """
  Turns autovacuum off for every entity table and Hologram's log, and returns :ok.

  A step's writes cross the log's autoanalyze threshold, and autovacuum's work would land in
  the counters as the step's, so the database runs none of its own: the driver vacuums and
  analyzes between steps instead. The setting survives TRUNCATE, so once per case is enough,
  after a server node has created the tables. A production database pays for autovacuum, which
  these figures leave out.
  """
  @spec disable_autovacuum!(pid) :: :ok
  def disable_autovacuum!(conn) do
    conn
    |> list_tables()
    |> Enum.each(&Postgrex.query!(conn, "ALTER TABLE #{&1} SET (autovacuum_enabled = false)", []))
  end

  @doc """
  Empties every entity table and Hologram's log, and returns :ok.

  For the start of a case, with no server node running. The tables are read from the catalog,
  so a case's entity, a role grant table or a join table needs no listing here, and a database
  no server node has set up yet, which has none of them, is left as it is.
  """
  @spec reset!(pid) :: :ok
  def reset!(conn) do
    truncate!(conn, list_tables(conn))
  end

  @doc """
  Returns how many rows the given entity table holds.
  """
  @spec row_count(pid, String.t()) :: non_neg_integer
  def row_count(conn, table) do
    %{rows: [[count]]} =
      Postgrex.query!(
        conn,
        "SELECT count(*) FROM #{qualified(Mapper.data_schema(), table)}",
        [],
        timeout: :infinity
      )

    count
  end

  @doc """
  Returns how far the given counters moved from the earlier ones.
  """
  @spec stats_delta(stats, stats) :: stats
  def stats_delta(later, earlier) do
    Map.new(later, fn {key, value} -> {key, value - Map.fetch!(earlier, key)} end)
  end

  @doc """
  Waits for the counters to settle, then returns them.

  Called after a phase, so what the phase's backends did is in them, and before one, so what came
  earlier is too and the difference is the phase's alone.
  """
  @spec settled_stats(pid) :: stats
  def settled_stats(conn) do
    Process.sleep(@settle_ms)

    stats(conn)
  end

  @doc """
  Returns the database's counters as they stand: committed transactions, rows read by scans,
  rows fetched by index lookups and the milliseconds backends spent running statements.

  The rows read by scans and by lookups stay apart, since summing them counts a lookup twice:
  an index scan adds to both.

  `:at_ms` is when they were read, so a difference of two reads carries the time between them.

  The counters cover the whole database, not one node: this read itself adds a commit and some
  catalog rows, and so do autovacuum's workers. A phase's figure is the difference between two
  reads, with the idle rate subtracted where the phase has one.
  """
  @spec stats(pid) :: stats
  def stats(conn) do
    %{rows: [[xact_commit, tup_returned, tup_fetched, active_ms]]} =
      Postgrex.query!(
        conn,
        """
        SELECT xact_commit, tup_returned, tup_fetched, active_time
        FROM pg_stat_database
        WHERE datname = current_database()
        """,
        []
      )

    %{
      active_ms: active_ms,
      at_ms: System.monotonic_time(:millisecond),
      tup_fetched: tup_fetched,
      tup_returned: tup_returned,
      xact_commit: xact_commit
    }
  end

  @doc """
  Empties Hologram's log and mutation record, and returns :ok.

  For between the steps of a case, with no server node running: each step starts from an empty
  log, so what a step reads of it is its own.
  """
  @spec truncate_log!(pid) :: :ok
  def truncate_log!(conn) do
    truncate!(conn, log_tables())
  end

  @doc """
  Refreshes the planner's statistics and the visibility map after seeding, and returns :ok, so a
  case starts from the plans a settled database gets rather than from ones for empty tables.
  """
  @spec vacuum_analyze!(pid) :: :ok
  def vacuum_analyze!(conn) do
    Postgrex.query!(conn, "VACUUM ANALYZE", [], timeout: :infinity)

    :ok
  end

  defp list_tables(conn) do
    %{rows: rows} =
      Postgrex.query!(
        conn,
        """
        SELECT table_schema, table_name
        FROM information_schema.tables
        WHERE table_schema = $1 OR (table_schema = $2 AND table_name = ANY($3))
        """,
        [Mapper.data_schema(), Mapper.system_schema(), @log_tables]
      )

    Enum.map(rows, fn [schema, table] -> qualified(schema, table) end)
  end

  defp log_tables do
    Enum.map(@log_tables, &qualified(Mapper.system_schema(), &1))
  end

  defp qualified(schema, table) do
    "#{Mapper.quote_identifier(schema)}.#{Mapper.quote_identifier(table)}"
  end

  # No CASCADE: every table a reset empties is named, so a table referencing one of them from
  # outside the list fails the reset rather than being emptied unnoticed.
  defp truncate!(_conn, []), do: :ok

  defp truncate!(conn, tables) do
    Postgrex.query!(conn, "TRUNCATE #{Enum.join(tables, ", ")} RESTART IDENTITY", [],
      timeout: :infinity
    )

    :ok
  end
end
