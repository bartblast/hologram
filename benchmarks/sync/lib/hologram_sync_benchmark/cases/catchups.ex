defmodule HologramSyncBenchmark.Cases.Catchups do
  @moduledoc false

  # credo:disable-for-this-file Credo.Check.Refactor.IoPuts

  # How many catch-ups a node should run at once. It's fixed at 4 for now (see
  # `Hologram.Sync.Gate`): more finishes a wave sooner and takes more of the database from the app's
  # own requests. This runs the same reconnect wave at each number, with sync's pool sized to match
  # as it is by default, and sets how long the queue takes to clear against how slow the app gets.
  #
  # The library has no setting for the number, so the deployed node's gate is told it directly, and
  # no part of the library changes. Every number runs whatever the one before it did: the smallest
  # is the likeliest to miss the wave's limit, and the ones after it are the point.

  alias Hologram.Sync.Gate
  alias Hologram.Sync.Pool
  alias HologramSyncBenchmark.Cases.Reconnect
  alias HologramSyncBenchmark.Clients
  alias HologramSyncBenchmark.DB
  alias HologramSyncBenchmark.Measure
  alias HologramSyncBenchmark.Peer
  alias HologramSyncBenchmark.Report
  alias HologramSyncBenchmark.Sweep

  @default_clients 1_000

  @default_limits [1, 2, 4, 8, 16]

  # Connections a wave's node and the driver need besides sync's pool: the app's pool of 10, the
  # node's listener, and the driver's own for its counters and its sampler.
  @connections_besides_pool 15

  @doc """
  Runs the case with the given options, writes its section into the README, and returns :ok.
  """
  @spec run(pid, keyword) :: :ok
  def run(conn, opts) do
    limits = opts[:catchups] || @default_limits
    count = Clients.single_count!(opts[:clients], @default_clients)
    wave = Reconnect.sweep_case(opts, :board)
    memory_limit = opts[:memory_limit] * 1_073_741_824

    :ok = wave.check!.([count])
    :ok = check_connections!(conn, Enum.max(limits))
    :ok = Clients.check_limits!(count, Reconnect.burst(count, opts[:wave_spread_ms]))
    :ok = Report.check_readme!()
    run_line = Report.run_line(conn)

    cookie_paths = wave.seed.(conn, count)

    results =
      limits
      |> Enum.with_index()
      |> Enum.map(fn {limit, index} ->
        IO.puts("Catch-ups at once: #{limit}")

        # Numbered apart per limit: the cards keep the markers an earlier run wrote, and a client
        # filling them would take one as this run's write arriving before it was made.
        first_marker = index * Sweep.markers_per_step()

        outcome = run_limit(conn, wave, {limit, count, first_marker}, cookie_paths, memory_limit)
        result = take_outcome(outcome, wave, limit)

        IO.puts(result.line)

        result
      end)

    # With nothing measured there's nothing to write, and writing would replace an earlier run's
    # good section with an empty one.
    if Enum.all?(results, &is_nil(&1.wave)) do
      raise "no number of catch-ups was measured: #{inspect(Enum.map(results, & &1.line))}"
    end

    figure = figure(results)
    IO.puts("Queue cleared after the last client came back: #{figure}")

    Report.write_case!(
      "catchups" <> Reconnect.suffix(opts),
      "How many catch-ups a node runs at once#{Reconnect.title_suffix(opts)}",
      run_line,
      options(wave, count, limits, opts),
      figure,
      [{"Per number of catch-ups at once", columns(), Enum.map(results, &row/1)}],
      figure_label: "Queue cleared after the last client came back"
    )
  end

  @doc """
  Sets how many catch-ups the node's gate lets in at once and returns the gate, raising when sync's
  pool isn't the given size. Runs on the server node, before any client comes back.
  """
  @spec set_gate_limit(pos_integer) :: pid
  def set_gate_limit(limit) do
    if Pool.size() != limit do
      raise "sync's pool has #{Pool.size()} connections, not #{limit}"
    end

    _state = :sys.replace_state(Gate, &%{&1 | limit: limit})

    Process.whereis(Gate)
  end

  @doc """
  Returns the node's gate. Runs on the server node.
  """
  @spec gate :: pid | nil
  def gate, do: Process.whereis(Gate)

  defp check_connections!(conn, most) do
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

    needed = most + @connections_besides_pool
    free = max - reserved - open

    if needed > free do
      raise "#{most} catch-ups at once need about #{needed} connections, Postgres has #{free} free"
    end

    :ok
  end

  # The first node fills the clients with the default pool, since only the wave is being compared.
  # A failure at one number leaves the others to run.
  defp run_limit(conn, wave, {limit, count, first_marker}, cookie_paths, memory_limit) do
    :ok = DB.truncate_log!(conn)
    :ok = DB.vacuum_analyze!(conn)
    autovacuum_before = DB.autovacuum_runs(conn)

    case Sweep.prepare_guarded(
           memory_limit,
           &wave.before_step.(conn, &1, count, first_marker, cookie_paths),
           wave.after_step
         ) do
      {:ok, prepared} ->
        try do
          conn
          |> run_wave(wave, {limit, count, first_marker}, prepared, memory_limit)
          |> with_log_counts(conn, autovacuum_before)
        after
          wave.after_step.(prepared)
        end

      {:stopped, _memory} ->
        :stopped_filling
    end
  catch
    kind, reason -> {:failed, Report.short_reason(kind, reason)}
  end

  # Sync's pool is sized to the number, as it is by default, through the env the next node copies.
  defp run_wave(conn, wave, {limit, count, first_marker}, prepared, memory_limit) do
    sync_env = Application.get_env(:hologram, :sync)

    Application.put_env(
      :hologram,
      :sync,
      Keyword.put(sync_env || [], :pool_size, limit)
    )

    try do
      Sweep.with_guarded_peer(memory_limit, fn peer ->
        gate = Peer.rpc(peer, __MODULE__, :set_gate_limit, [limit])
        result = wave.step.(conn, peer, count, first_marker, prepared)

        # A gate that restarted went back to the default, so the row wouldn't be this number's.
        if Peer.rpc(peer, __MODULE__, :gate, []) != gate do
          raise "the gate restarted during the wave"
        end

        result
      end)
    after
      restore_sync_env(sync_env)
    end
  end

  defp restore_sync_env(nil), do: Application.delete_env(:hologram, :sync)

  defp restore_sync_env(sync_env), do: Application.put_env(:hologram, :sync, sync_env)

  defp with_log_counts({:ok, result}, conn, autovacuum_before) do
    {:ok,
     Map.merge(result, %{
       autovacuum_ran: DB.autovacuum_runs(conn) != autovacuum_before,
       heap_kills: Measure.heap_kills(Peer.log_path()),
       session_cuts: Measure.session_cuts(Peer.log_path())
     })}
  end

  defp with_log_counts(stopped, _conn, _autovacuum_before), do: stopped

  defp take_outcome({:ok, result}, wave, limit) do
    passed = wave.passed?.(result)
    result = Map.put(result, :passed, passed)

    %{
      limit: limit,
      line: wave.summary.(result),
      note: if(passed, do: nil, else: wave.why.(result)),
      wave: result
    }
  end

  defp take_outcome({:stopped, _memory}, _wave, limit) do
    %{limit: limit, line: "  STOPPED at the memory limit", note: "memory limit", wave: nil}
  end

  defp take_outcome(:stopped_filling, _wave, limit) do
    note = "memory limit while filling on the first node, before the wave"

    %{limit: limit, line: "  STOPPED at the #{note}", note: note, wave: nil}
  end

  defp take_outcome({:failed, message}, _wave, limit) do
    %{limit: limit, line: "  FAILED: #{message}", note: message, wave: nil}
  end

  defp options(wave, count, limits, opts) do
    wave.options ++
      [
        "#{count} anonymous clients",
        "the same wave at #{Enum.join(limits, ", ")} catch-ups at once, with sync's database " <>
          "pool the same size, each on a fresh log and fresh nodes",
        "a wave passes when every client is caught up within #{opts[:wave_limit]} s of the " <>
          "first one coming back and holds every write it should within " <>
          "#{Reconnect.drain_seconds()} s after that and no other"
      ]
  end

  defp figure(results) do
    Enum.map_join(results, ", ", fn
      %{limit: limit, wave: %{after_last_return_ms: ms, passed: true}} ->
        "#{Report.cell(ms / 1_000)} s at #{limit}"

      %{limit: limit} ->
        "failed at #{limit}"
    end)
  end

  defp columns do
    [
      "Catch-ups at once",
      "Caught up",
      "Last caught up ms",
      "After the last return ms",
      "Return restarts",
      "Own wait p50 ms",
      "Own wait p99 ms",
      "Server CPU s",
      "DB ms",
      "Peak sync backends",
      "App p50 ms during",
      "App p99 ms during",
      "App requests failed",
      "Step passed",
      "Why not"
    ]
  end

  defp row(%{limit: limit, note: note, wave: nil}) do
    [limit, "-", nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, "no", note]
  end

  defp row(%{limit: limit, note: note, wave: wave}) do
    [
      limit,
      "#{wave.caught_up}/#{wave.clients}",
      wave.last_caught_up_ms,
      wave.after_last_return_ms,
      wave.return_restarts,
      Measure.percentile(wave.waits_ms, 50),
      Measure.percentile(wave.waits_ms, 99),
      wave.cpu_ms && wave.cpu_ms / 1_000,
      wave.db && wave.db.active_ms,
      wave.peak_backends.sync,
      wave.probe_wave.p50_ms,
      wave.probe_wave.p99_ms,
      wave.probe_wave.failures,
      Report.passed_cell(wave),
      note
    ]
  end
end
