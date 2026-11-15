defmodule HologramSyncBenchmark.Cases.Deploy do
  @moduledoc false

  # A deploy that changes the read rules: every open tab comes back at once, each sent the new
  # rules and everything it may read again, since what it holds was picked under the old ones.
  # Run on the board's data or the tenants' data. Each step connects all its clients at the same
  # moment and times until the last of them holds its whole pot again.
  #
  # The clients come back with no cursor, greeting with a policy hash that isn't the server's. A
  # client whose cursor names other rules is told to start over and then filled exactly as one
  # with no cursor (`Hologram.Sync.Catchup.gap/3` checks the rules before reading the log), so the
  # server's cost is the same, and this doesn't depend on the cursor's format, which the pivot
  # changes. The stale hash is what makes the server send its rules, as after a real deploy. After
  # the pivot a returning browser reports what it holds, so a real refill may cost less than this.
  # One thing points the other way: a real browser also greets with its replica id and token,
  # which the server verifies and looks up with one pooled query per client before the session
  # starts. These clients make no writes, so they send none, and a burst here leaves those out.

  alias HologramSyncBenchmark.Cases.Board
  alias HologramSyncBenchmark.Cases.Tenants
  alias HologramSyncBenchmark.Client
  alias HologramSyncBenchmark.Clients
  alias HologramSyncBenchmark.DB
  alias HologramSyncBenchmark.Measure
  alias HologramSyncBenchmark.Report
  alias HologramSyncBenchmark.Step

  # 200 and 500 between, since a refill measured about 14 MB per client, so the memory limit lands
  # around a few hundred.
  @counts [10, 100, 200, 500, 1_000, 5_000]

  # Any hash other than the server's, as a bundle built before the deploy has.
  @stale_policy_hash "rules-before-the-deploy"

  @doc """
  Returns the deploy case on the given data, `:board` or `:tenants`, for the given options.
  """
  @spec sweep_case(keyword, :board | :tenants) :: map
  def sweep_case(opts, data) do
    source = source(opts, data)

    %{
      burst: &Enum.max/1,
      check!: source.check!,
      clients: "#{source.clients}, connecting all at once with a stale policy hash and no cursor",
      counts: source.counts,
      name: if(data == :board, do: "deploy", else: "deploy_tenants"),
      options: source.options,
      passed?: &passed?(&1, opts),
      seed: source.seed,
      step: &step(&1, &2, &3, &4, &5, opts, source.page),
      step_options: [
        "a step passes when every client holds its whole pot again within " <>
          "#{opts[:refill_limit]} s of the first connect"
      ],
      summary: &summary/1,
      tables: &tables/1,
      title: "Reconnect after a rules deploy, #{source.title}"
    }
  end

  defp passed?(result, opts) do
    %{fill: fill} = result

    # A client never sent the rules wasn't treated as one coming back after a deploy, so its fill
    # was a plain first visit's.
    fill.failed == 0 and fill.unfinished == 0 and fill.connect_failures == 0 and
      result.rules_sent == result.clients and result.last_refill_ms != nil and
      result.last_refill_ms <= opts[:refill_limit] * 1_000
  end

  # The board's or the tenants' seeding and client counts, so the clients reconnect to the data
  # and rules those cases measure writes on.
  defp source(opts, :board) do
    board = Board.sweep_case(opts, :plain)

    %{
      check!: fn _counts -> :ok end,
      clients: board.clients,
      counts: @counts,
      options: board.options,
      page: "HologramSyncBenchmark.BoardPage",
      seed: board.seed,
      title: "shared board"
    }
  end

  defp source(opts, :tenants) do
    tenants = Tenants.sweep_case(opts)
    users = opts[:tenants] * opts[:members]

    %{
      check!: fn counts ->
        if Enum.max(counts) > users do
          raise ArgumentError,
                "#{Enum.max(counts)} clients need more users than the #{users} seeded"
        end

        :ok
      end,
      clients: tenants.clients,
      counts: Enum.filter(@counts, &(&1 <= users)),
      options: tenants.options,
      page: "HologramSyncBenchmark.TasksPage",
      seed: tenants.seed,
      title: "multi-tenant app"
    }
  end

  defp step(conn, peer, count, _first_marker, cookie_paths, opts, page) do
    base =
      peer
      |> Clients.base_opts(page)
      |> Keyword.put(:policy_hash, @stale_policy_hash)

    clients =
      cookie_paths
      |> Enum.take(count)
      |> Enum.map(&Keyword.put(base, :cookie_path, &1))
      |> Clients.start_all()

    try do
      Clients.prepare_all!(clients, Step.connect_concurrency())

      memory_before = Measure.memory(peer, collect: true)
      poller = Measure.start_memory_peak(peer)

      fill =
        Step.fill(peer, clients, %{
          conn: conn,
          connect_concurrency: count,
          # Waited on no longer than a passing step may take: past it the step fails anyway.
          fill_timeout_ms: opts[:refill_limit] * 1_000
        })

      memory_rise = Measure.stop_memory_peak(poller)
      memory_after = Measure.memory(peer)
      reports = Enum.map(clients, &Client.report/1)

      idle = Step.idle(peer, %{conn: conn}, DB.settled_stats(conn))

      %{
        clients: count,
        fill: %{
          fill
          | cpu_ms: fill.cpu_ms - idle.cpu_ms_per_ms * fill.cpu_elapsed_ms,
            db: Step.adjust(fill.db, idle.db)
        },
        connect_retries: Enum.sum_by(reports, & &1.connect_retries),
        last_refill_ms: last_refill_ms(reports),
        memory_per_client:
          if(count >= Step.memory_min_clients(), do: (memory_after - memory_before) / count),
        memory_rise: memory_rise,
        rules_sent: Enum.count(reports, &(&1.rules_at != nil))
      }
    after
      Clients.close_all(clients)
    end
  end

  # From the first connect of the burst to the last client holding its whole pot, or nil when one
  # never did.
  defp last_refill_ms(reports) do
    if Enum.all?(reports, &(&1.synced_all_at != nil)) do
      first_connect = Enum.min_by(reports, & &1.connected_at).connected_at
      last_synced = Enum.max_by(reports, & &1.synced_all_at).synced_all_at

      (last_synced - first_connect) / 1_000
    end
  end

  defp summary(result) do
    %{fill: fill} = result

    "  #{if result.passed, do: "passed", else: "FAILED"}, " <>
      "#{fill.filled}/#{result.clients} refilled, rules sent to #{result.rules_sent}, " <>
      "last refill #{Report.cell(result.last_refill_ms)} ms, " <>
      "p99 #{Report.cell(Measure.percentile(fill.ms, 99))} ms, " <>
      "#{Report.cell(fill.cpu_ms / 1_000)} CPU s, " <>
      "memory rise #{Report.cell(result.memory_rise / 1_048_576)} MB, " <>
      "#{result.connect_retries} connect retries, " <>
      "#{fill.restarts} restarts, #{result.heap_kills} heap kills" <>
      if(result.heap_kills != fill.restarts, do: " (MISMATCH)", else: "") <>
      if(result.autovacuum_ran, do: ", AUTOVACUUM RAN", else: "")
  end

  defp tables(results) do
    columns = [
      "Clients",
      "Refilled",
      "Rules sent",
      "Last refill ms",
      "Refill p50 ms",
      "Refill p99 ms",
      "Connect retries",
      "Fills restarted",
      "Heap kills",
      "Server CPU s",
      "DB rows scanned",
      "Memory rise MB",
      "KB per client",
      "Step passed"
    ]

    rows =
      Enum.map(results, fn result ->
        %{fill: fill} = result

        [
          result.clients,
          "#{fill.filled}/#{result.clients}",
          result.rules_sent,
          result.last_refill_ms,
          Measure.percentile(fill.ms, 50),
          Measure.percentile(fill.ms, 99),
          result.connect_retries,
          fill.restarts,
          result.heap_kills,
          fill.cpu_ms / 1_000,
          fill.db.tup_returned,
          result.memory_rise / 1_048_576,
          result.memory_per_client && result.memory_per_client / 1_024,
          Report.passed_cell(result)
        ]
      end)

    [{"Refill", columns, rows}]
  end
end
