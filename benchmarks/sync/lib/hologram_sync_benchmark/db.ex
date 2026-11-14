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

  # Hologram's own tables a case's runs fill: the log and the record of browser batches.
  @log_tables ["oplog", "mutation"]

  @type stats :: %{
          active_ms: float,
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
  Empties every entity table and Hologram's log, and returns :ok.

  For the start of a case, with no server node running. The tables are read from the catalog,
  so a case's entity, a role grant table or a join table needs no listing here, and a database
  no server node has set up yet, which has none of them, is left as it is.
  """
  @spec reset!(pid) :: :ok
  def reset!(conn) do
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

    tables = Enum.map(rows, fn [schema, table] -> qualified(schema, table) end)

    truncate!(conn, tables)
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
