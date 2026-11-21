defmodule HologramSyncBenchmark.Cases.Reconnect do
  @moduledoc false

  # A deploy that changes neither the data model nor the rules: every stream closes, a few writes
  # land while the clients are away, a new node starts, and every client comes back within seconds
  # with the place it had. Each is told only what it missed, so this is the catch-up path, where
  # the deploy cases are the refill one. A client told to start over fails the step, so a wave that
  # quietly turned into a refill can't pass.
  #
  # A step runs on two server nodes. The first fills the clients and takes the writes made while
  # they're away (`prepare/7`). The second is the deployed node, started cold, and only its work is
  # measured (`step/6`): how long until the last client is caught up, what that cost the node and
  # the database, and how slow the app's own requests got meanwhile.

  alias Hologram.Sync.Catchup
  alias HologramSyncBenchmark.Cases.Board
  alias HologramSyncBenchmark.Cases.Tenants
  alias HologramSyncBenchmark.Client
  alias HologramSyncBenchmark.Clients
  alias HologramSyncBenchmark.DB
  alias HologramSyncBenchmark.Entities.Card
  alias HologramSyncBenchmark.Entities.Task
  alias HologramSyncBenchmark.Measure
  alias HologramSyncBenchmark.Peer
  alias HologramSyncBenchmark.Probe
  alias HologramSyncBenchmark.Report
  alias HologramSyncBenchmark.Step
  alias HologramSyncBenchmark.Writer

  # How long the app's requests are timed before the wave, and how much of the probe's start is
  # left out of it, since its first requests pay for a cold node's code and connections.
  @baseline_ms 5_000

  @baseline_warmup_ms 1_000

  @counts [100, 500, 1_000, 2_000, 5_000]

  @doc """
  Returns the reconnect case on the given data, `:board` or `:tenants`, for the given options.
  """
  @spec sweep_case(keyword, :board | :tenants) :: map
  def sweep_case(opts, data) do
    source = source(opts, data)

    %{
      after_step: &close_clients/1,
      before_step: &prepare(&1, &2, &3, &4, &5, opts, source),
      # Spread over the wave rather than all at once, so what reaches the listen backlog is about
      # one second's share.
      burst: &max(div(Enum.max(&1), opts[:wave_spread]), 1),
      check!: &check!(&1, opts, source),
      clients: "#{source.clients}, coming back with their places after a node restart",
      counts: source.counts,
      name: if(data == :board, do: "reconnect", else: "reconnect_tenants"),
      options: [
        source.data,
        "#{opts[:gap_writes]} writes made while the clients are away, each to a row of its own",
        "each client comes back at a random moment within #{opts[:wave_spread]} s"
      ],
      passed?: &passed?(&1, opts),
      seed: source.seed,
      step: &step(&1, &2, &3, &4, &5, opts),
      step_options: [
        "a step passes when every client is caught up within #{opts[:wave_limit]} s of the " <>
          "first one coming back, holding every write it should and no other, with none told to " <>
          "start over"
      ],
      summary: &summary/1,
      tables: &tables/1,
      title: "Reconnect wave after a deploy, #{source.title}",
      why: &why_failed(&1, opts)
    }
  end

  defp source(opts, :board) do
    board = Board.sweep_case(opts, :plain)

    %{
      clients: board.clients,
      counts: @counts,
      data: board.data,
      rows: opts[:cards],
      seed: board.seed,
      spec: board.spec,
      title: "shared board",
      type: Card,
      users: nil
    }
  end

  defp source(opts, :tenants) do
    tenants = Tenants.sweep_case(opts)
    users = opts[:tenants] * opts[:members]

    %{
      clients: tenants.clients,
      # Fewer users than the smallest count still get a step, of every user.
      counts:
        case Enum.filter(@counts, &(&1 <= users)) do
          [] -> [users]
          counts -> counts
        end,
      data: tenants.data,
      rows: opts[:tenants] * opts[:tasks],
      seed: tenants.seed,
      spec: tenants.spec,
      title: "multi-tenant app",
      type: Task,
      users: users
    }
  end

  # Each write goes to a row of its own, since a client's catch-up reads a row as it stands, and a
  # second write to one row would take the first one's marker with it. Past the gap limit a client
  # is sent everything again, which isn't what this case measures.
  defp check!(counts, opts, source) do
    if source.users && Enum.max(counts) > source.users do
      raise ArgumentError,
            "#{Enum.max(counts)} clients need more users than the #{source.users} seeded"
    end

    if opts[:gap_writes] > reachable_rows(Enum.min(counts), opts, source) do
      raise ArgumentError,
            "#{opts[:gap_writes]} writes need a row each, more than the fewest clients read"
    end

    if opts[:gap_writes] > Catchup.gap_limit() do
      raise ArgumentError,
            "#{opts[:gap_writes]} writes are past the #{Catchup.gap_limit()} a catch-up replays"
    end

    :ok
  end

  # The tenants case's writes walk the tenants with clients connected.
  defp reachable_rows(_count, _opts, %{users: nil} = source), do: source.rows

  defp reachable_rows(count, opts, _source) do
    div(count + opts[:members] - 1, opts[:members]) * opts[:tasks]
  end

  # On the first node: a write so the log has something below every client's place, the clients
  # filled, then gone, then the writes they'll have missed. Returns what the step needs.
  defp prepare(conn, peer, count, first_marker, cookie_paths, opts, source) do
    spec = source.spec.(conn, count, first_marker, cookie_paths)
    rows = spec.rows.(peer)

    :ok = Peer.rpc(peer, Writer, :warm_up, [source.type, elem(rows, 0), :title, "warm-up"])

    clients =
      peer
      |> spec.client_opts.()
      |> Clients.start_all()

    try do
      Clients.prepare_all!(clients, Step.connect_concurrency())

      connect_failures = Clients.connect_all(clients, Step.connect_concurrency())
      fills = Clients.await_fills(clients, opts[:fill_timeout] * 1_000)
      left_out = Clients.leave_all(clients)

      # One that couldn't leave has no place to come back with. Left to retry, it would run a cold
      # fill on the deployed node, in the middle of what's being measured.
      Enum.each(left_out, fn {client, _reason} -> Client.give_up(client) end)

      numbers = Enum.map(0..(opts[:gap_writes] - 1), &(first_marker + &1))

      for number <- numbers do
        spec.write.(peer, rows, number - first_marker, number)
      end

      :ok = Peer.sync_log(peer)

      %{
        clients: clients,
        expected: fn number -> spec.expected.(number - first_marker) end,
        fill: %{
          connect_failures: length(connect_failures),
          failed: Enum.count(fills, &(&1.failure != nil)),
          heap_kills: Measure.heap_kills(peer.log_path),
          restarts: Enum.sum_by(fills, & &1.restarts),
          session_cuts: Measure.session_cuts(peer.log_path),
          unfinished: Enum.count(fills, &(&1.synced_all_at == nil and &1.failure == nil))
        },
        left_out: Enum.map(left_out, &elem(&1, 0)),
        numbers: numbers
      }
    catch
      kind, reason ->
        Clients.close_all(clients)
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  defp close_clients(%{clients: clients}), do: Clients.close_all(clients)

  # On the deployed node. The probe and the backend sampler run throughout, the idle window
  # included, so what they cost the database comes off the wave's figures with the idle rate.
  defp step(conn, peer, count, _first_marker, prepared, opts) do
    probe =
      peer
      |> Peer.base_url()
      |> Probe.start()

    backends = DB.start_backend_sampler()

    try do
      measure_wave(conn, peer, count, prepared, opts, probe, backends)
    catch
      kind, reason ->
        stop_quietly(fn -> Probe.stop(probe) end)
        stop_quietly(fn -> DB.stop_backend_sampler(backends) end)
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  defp measure_wave(conn, peer, count, prepared, opts, probe, backends) do
    Process.sleep(@baseline_warmup_ms)
    baseline_from = now_ms()
    Process.sleep(@baseline_ms)
    baseline_to = now_ms()

    stats_before = DB.settled_stats(conn)
    cpu_before = Measure.cpu_sample(peer)

    wave_from = now_ms()
    returning = prepared.clients -- prepared.left_out
    :ok = Clients.come_back_all(returning, opts[:wave_spread] * 1_000)
    _reports = Clients.await_caught_up(returning, opts[:wave_limit] * 1_000)
    wave_to = now_ms()

    cpu_after = Measure.cpu_sample(peer)
    reports = Enum.map(prepared.clients, &Client.report/1)

    {cpu_ms, db} = wave_cost(conn, peer, reports, {cpu_before, cpu_after}, stats_before)

    samples = Probe.stop(probe)
    peak_backends = DB.stop_backend_sampler(backends)

    writes = Map.new(prepared.numbers, &{&1, 0})
    {_times, missing} = Measure.latencies(writes, reports, prepared.expected)

    %{
      caught_up: Enum.count(reports, &(&1.caught_up_at != nil)),
      clients: count,
      cpu_ms: cpu_ms,
      db: db,
      failed: Enum.count(reports, &(&1.failure != nil)),
      fill: prepared.fill,
      last_caught_up_ms: last_caught_up_ms(reports),
      leaked: Measure.leaks(writes, reports, prepared.expected),
      left_out: length(prepared.left_out),
      missing: missing,
      peak_backends: peak_backends,
      probe_baseline: Probe.summary(samples, baseline_from, baseline_to),
      probe_wave: Probe.summary(samples, wave_from, wave_to),
      return_restarts: Enum.sum_by(reports, & &1.return_restarts),
      waits_ms: waits_ms(reports)
    }
  end

  # What the wave cost the server and the database, with the idle rate taken off. Nil for a wave
  # some client never finished: it would still be at work in the idle window, so the rate taken
  # off would hold the wave's own work, scaled up.
  defp wave_cost(conn, peer, reports, {cpu_before, cpu_after}, stats_before) do
    if Enum.all?(reports, &(&1.caught_up_at != nil)) do
      stats_after = DB.settled_stats(conn)
      idle = Step.idle(peer, %{conn: conn}, stats_after)

      cpu_ms =
        Measure.cpu_ms(cpu_before, cpu_after) -
          idle.cpu_ms_per_ms * Measure.elapsed_ms(cpu_before, cpu_after)

      db =
        stats_after
        |> DB.stats_delta(stats_before)
        |> Step.adjust(idle.db)

      {cpu_ms, db}
    else
      {nil, nil}
    end
  end

  # Never raises: it runs while another failure is on its way up, and mustn't replace it.
  defp stop_quietly(stop) do
    _stopped = stop.()

    :ok
  catch
    _kind, _reason -> :ok
  end

  # From the first client coming back to the last one holding its whole pot again, or nil when one
  # never did.
  defp last_caught_up_ms(reports) do
    if Enum.all?(reports, &(&1.caught_up_at != nil)) do
      first_back = Enum.min_by(reports, & &1.returned_at).returned_at
      last_caught_up = Enum.max_by(reports, & &1.caught_up_at).caught_up_at

      (last_caught_up - first_back) / 1_000
    end
  end

  defp waits_ms(reports) do
    for %{caught_up_at: caught_up_at, returned_at: returned_at} <- reports,
        caught_up_at != nil,
        do: (caught_up_at - returned_at) / 1_000
  end

  defp passed?(result, opts) do
    why_failed(result, opts) == ""
  end

  defp why_failed(result, opts) do
    (fill_reasons(result.fill) ++ wave_reasons(result, opts))
    |> Enum.filter(& &1)
    |> Enum.join(", ")
  end

  defp fill_reasons(fill) do
    [
      fill.failed > 0 && "#{fill.failed} failed their first fill",
      fill.unfinished > 0 && "#{fill.unfinished} never filled",
      fill.connect_failures > 0 && "#{fill.connect_failures} couldn't connect"
    ]
  end

  defp wave_reasons(result, opts) do
    [
      result.left_out > 0 && "#{result.left_out} couldn't leave",
      result.failed > result.left_out && "#{result.failed - result.left_out} failed coming back",
      result.caught_up < result.clients &&
        "#{result.clients - result.caught_up} never caught up",
      result.missing > 0 && "#{result.missing} deliveries missing",
      result.leaked > 0 && "#{result.leaked} deliveries leaked",
      slow_wave?(result, opts) && "the last client took #{round(result.last_caught_up_ms)} ms"
    ]
  end

  defp slow_wave?(%{last_caught_up_ms: nil}, _opts), do: false

  defp slow_wave?(result, opts), do: result.last_caught_up_ms > opts[:wave_limit] * 1_000

  defp summary(result) do
    "  #{if result.passed, do: "passed", else: "FAILED"}, " <>
      "#{result.caught_up}/#{result.clients} caught up, " <>
      "last #{Report.cell(result.last_caught_up_ms)} ms, " <>
      "own wait p99 #{Report.cell(Measure.percentile(result.waits_ms, 99))} ms, " <>
      "#{Report.cell(result.cpu_ms && result.cpu_ms / 1_000)} CPU s, " <>
      "#{Report.cell(result.db && result.db.active_ms)} DB ms, " <>
      "peak #{Report.cell(result.peak_backends.sync)} sync and " <>
      "#{Report.cell(result.peak_backends.other)} other backends, " <>
      "app p99 #{Report.cell(result.probe_baseline.p99_ms)} ms before, " <>
      "#{Report.cell(result.probe_wave.p99_ms)} ms during, " <>
      "#{result.probe_wave.failures} app requests failed, " <>
      "#{result.return_restarts} return restarts, " <>
      "#{result.fill.heap_kills + result.heap_kills} heap kills, " <>
      "#{result.fill.session_cuts + result.session_cuts} sessions cut" <>
      if(result.autovacuum_ran, do: ", AUTOVACUUM RAN", else: "")
  end

  defp tables(results) do
    columns = [
      "Clients",
      "Caught up",
      "Last caught up ms",
      "Own wait p50 ms",
      "Own wait p99 ms",
      "Return restarts",
      "Heap kills",
      "Sessions cut",
      "Server CPU s",
      "DB commits",
      "DB rows scanned",
      "DB ms",
      "Peak sync backends",
      "Peak other backends",
      "App p50 ms before",
      "App p99 ms before",
      "App p50 ms during",
      "App p99 ms during",
      "App requests failed",
      "Step passed"
    ]

    rows =
      Enum.map(results, fn result ->
        [
          result.clients,
          "#{result.caught_up}/#{result.clients}",
          result.last_caught_up_ms,
          Measure.percentile(result.waits_ms, 50),
          Measure.percentile(result.waits_ms, 99),
          result.return_restarts,
          result.fill.heap_kills + result.heap_kills,
          result.fill.session_cuts + result.session_cuts,
          result.cpu_ms && result.cpu_ms / 1_000,
          result.db && result.db.xact_commit,
          result.db && result.db.tup_returned,
          result.db && result.db.active_ms,
          result.peak_backends.sync,
          result.peak_backends.other,
          result.probe_baseline.p50_ms,
          result.probe_baseline.p99_ms,
          result.probe_wave.p50_ms,
          result.probe_wave.p99_ms,
          result.probe_wave.failures,
          Report.passed_cell(result)
        ]
      end)

    [{"Wave", columns, rows}]
  end

  defp now_ms, do: System.monotonic_time(:millisecond)
end
