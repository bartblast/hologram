defmodule HologramSyncBenchmark.Step do
  @moduledoc false

  # One sweep step of a case with clients and writes: N clients fill, a few unmeasured writes warm
  # the node up, the clients take a few single writes, then a steady stream of them, then sit
  # idle, on a server node of their own. Each phase reads the server's CPU and the database's
  # counters, and the idle phase's rate of both is subtracted from the others, since heartbeats,
  # the dispatcher's poll and the driver's own reads go on whatever the writes do.

  alias HologramSyncBenchmark.Client
  alias HologramSyncBenchmark.Clients
  alias HologramSyncBenchmark.DB
  alias HologramSyncBenchmark.Measure
  alias HologramSyncBenchmark.Peer

  @connect_concurrency 50

  @drain_ms 10_000

  @idle_ms 10_000

  # The pause between single writes, after the last client got the one before.
  @isolated_gap_ms 1_000

  # How long a single write may take to reach its last client before the step stops waiting and
  # counts it as cut short: past it the write's work runs into the next one's.
  @isolated_wait_ms 10_000

  @isolated_writes 5

  # Below this many clients, the memory a step's clients take is smaller than what a node frees
  # and allocates on its own between two reads, so no figure is reported.
  @memory_min_clients 20

  @poll_ms 50

  # A fresh node's first writes pay for loaded code and caches, and each pooled database connection
  # pays once for its catalog lookups and prepared statements the first time it runs a statement,
  # which no later write does. The pool hands out its longest idle connection, so a write and the
  # sync work after it land on others each time, and this many writes reach every connection of a
  # pool of Hologram's default size more than once. Not measured.
  @warmup_writes 20

  @type spec :: %{
          client_opts: (Peer.t() -> [keyword]),
          conn: pid,
          duration_ms: pos_integer,
          expected: (non_neg_integer -> [non_neg_integer]),
          fill_timeout_ms: pos_integer,
          first_marker: non_neg_integer,
          rate: pos_integer,
          rows: (Peer.t() -> term),
          write: (Peer.t(), term, non_neg_integer, non_neg_integer -> integer)
        }

  @doc """
  Runs one step on the given server node and returns what it measured.

  `client_opts` gives one option list per client. `rows` reads, once per step and untimed, what
  the writes need to find their rows. `write` makes the step's write with the given offset, 0 up,
  setting the marker with the given number, and returns when it committed. `expected` names, for
  a write's offset, the indexes of the clients it should reach.

  Marker numbers run from `first_marker`, so no two steps of a sweep share one: the rows keep
  the values earlier steps wrote, and a client filling them would otherwise record an earlier
  step's marker as this step's write arriving before it was made.
  """
  @spec run(Peer.t(), spec) :: map
  def run(peer, spec) do
    rows = spec.rows.(peer)

    spec = %{
      spec
      | expected: fn number -> spec.expected.(number - spec.first_marker) end,
        write: fn peer, offset -> spec.write.(peer, rows, offset, spec.first_marker + offset) end
    }

    clients =
      peer
      |> spec.client_opts.()
      |> Clients.start_all()

    try do
      measure(peer, clients, spec)
    after
      Clients.close_all(clients)
    end
  end

  @doc """
  Returns how many clients a step connects at once.
  """
  @spec connect_concurrency :: pos_integer
  def connect_concurrency, do: @connect_concurrency

  @doc """
  Returns how many writes a step makes at the given rate per second for the given seconds, each to
  a row of its own.
  """
  @spec writes(pos_integer, pos_integer) :: pos_integer
  def writes(rate, duration_s) do
    @warmup_writes + @isolated_writes + rate * duration_s
  end

  defp adjust(delta, idle) do
    Map.new(delta, fn
      {:at_ms, value} -> {:at_ms, value}
      {key, value} -> {key, value - Map.fetch!(idle, key) / idle.at_ms * delta.at_ms}
    end)
  end

  defp await_delivery(clients, indexes, number, deadline) do
    delivered? = Enum.all?(indexes, &Client.has_marker?(elem(clients, &1), number))

    cond do
      delivered? ->
        true

      System.monotonic_time(:millisecond) >= deadline ->
        false

      true ->
        Process.sleep(@poll_ms)
        await_delivery(clients, indexes, number, deadline)
    end
  end

  # A write made and waited on until every client it should reach has it, or the wait ran out.
  defp await_write(peer, clients, spec, offset) do
    number = spec.first_marker + offset
    committed_at = spec.write.(peer, offset)
    deadline = System.monotonic_time(:millisecond) + @isolated_wait_ms

    {number, committed_at, await_delivery(clients, spec.expected.(number), number, deadline)}
  end

  defp collect(clients), do: Enum.map(clients, &Client.report/1)

  defp fill(peer, clients, spec) do
    stats_before = DB.settled_stats(spec.conn)
    cpu_before = Measure.cpu_sample(peer)

    connect_failures = Clients.connect_all(clients, @connect_concurrency)
    reports = Clients.await_fills(clients, spec.fill_timeout_ms)

    cpu_after = Measure.cpu_sample(peer)
    stats_after = DB.settled_stats(spec.conn)

    fill_ms =
      for %{connected_at: connected_at, synced_all_at: synced_all_at} <- reports,
          synced_all_at != nil,
          do: (synced_all_at - connected_at) / 1_000

    result = %{
      connect_failures: length(connect_failures),
      cpu_ms: Measure.cpu_ms(cpu_before, cpu_after),
      db: DB.stats_delta(stats_after, stats_before),
      failed: Enum.count(reports, &(&1.failure != nil)),
      filled: length(fill_ms),
      ms: fill_ms,
      restarts: Enum.sum_by(reports, & &1.restarts),
      unfinished: Enum.count(reports, &(&1.synced_all_at == nil and &1.failure == nil))
    }

    result
  end

  # Read last, once every write's work is over and the pool's connections are warm: read earlier,
  # a fresh node's backends still pay their first use during it, and the rate taken off the
  # other phases would be too high.
  defp idle(peer, spec, stats_before) do
    cpu_before = Measure.cpu_sample(peer)
    Process.sleep(@idle_ms)
    cpu_after = Measure.cpu_sample(peer)
    stats_after = DB.settled_stats(spec.conn)

    %{
      cpu_ms_per_ms:
        Measure.cpu_ms(cpu_before, cpu_after) / Measure.elapsed_ms(cpu_before, cpu_after),
      db: DB.stats_delta(stats_after, stats_before)
    }
  end

  # Single writes, each waited on until its last client has it, so its cost and its time to the
  # last client are its own, whatever rate the steady phase runs at. Raw: the idle rate is taken
  # off once the idle window has been read, after the writes.
  defp isolated(peer, clients, spec, stats_before) do
    writes =
      for offset <- @warmup_writes..(@warmup_writes + @isolated_writes - 1) do
        cpu_before = Measure.cpu_sample(peer)
        {number, committed_at, delivered?} = await_write(peer, clients, spec, offset)
        cpu_after = Measure.cpu_sample(peer)

        Process.sleep(@isolated_gap_ms)

        %{
          committed_at: committed_at,
          cpu_ms: Measure.cpu_ms(cpu_before, cpu_after),
          delivered?: delivered?,
          elapsed_ms: Measure.elapsed_ms(cpu_before, cpu_after),
          number: number
        }
      end

    stats_after = DB.settled_stats(spec.conn)

    reports =
      clients
      |> Tuple.to_list()
      |> collect()
      |> List.to_tuple()

    last_delivery_ms =
      for %{delivered?: true, committed_at: committed_at, number: number} <- writes do
        last_at =
          number
          |> spec.expected.()
          |> Enum.map(&Map.fetch!(elem(reports, &1).markers, number))
          |> Enum.max()

        (last_at - committed_at) / 1_000
      end

    raw = %{
      db: DB.stats_delta(stats_after, stats_before),
      last_delivery_ms: last_delivery_ms,
      writes: writes
    }

    {raw, stats_after}
  end

  defp finish_isolated(raw, idle) do
    cpu_ms = Enum.map(raw.writes, &(&1.cpu_ms - idle.cpu_ms_per_ms * &1.elapsed_ms))

    %{
      cpu_ms: Measure.percentile(cpu_ms, 50),
      # Writes the step stopped waiting for: their work ran into the next write's, so the CPU
      # figure overstates and the delivery figure leaves them out.
      cut_short: Enum.count(raw.writes, &(not &1.delivered?)),
      db: per_write(adjust(raw.db, idle.db), @isolated_writes),
      last_delivery_ms: Measure.percentile(raw.last_delivery_ms, 50)
    }
  end

  defp finish_steady(raw, idle) do
    cpu_ms = raw.cpu_ms - idle.cpu_ms_per_ms * raw.elapsed_ms

    raw
    |> Map.drop([:cpu_ms, :elapsed_ms])
    |> Map.merge(%{
      cpu_ms_per_write: cpu_ms / raw.writes,
      db: per_write(adjust(raw.db, idle.db), raw.writes)
    })
  end

  defp measure(peer, clients, spec) do
    [] = Clients.prepare_all(clients, @connect_concurrency)

    memory_before = Measure.memory(peer)
    fill = fill(peer, clients, spec)
    memory_after = Measure.memory(peer)

    client_tuple = List.to_tuple(clients)

    # Waited on, so their deliveries are over before anything is measured.
    for offset <- 0..(@warmup_writes - 1), do: await_write(peer, client_tuple, spec, offset)

    stats_before_isolated = DB.settled_stats(spec.conn)
    {isolated, stats_after_isolated} = isolated(peer, client_tuple, spec, stats_before_isolated)
    {steady, stats_after_steady} = steady(peer, clients, spec, stats_after_isolated)
    idle = idle(peer, spec, stats_after_steady)

    memory_per_client =
      if length(clients) >= @memory_min_clients do
        (memory_after - memory_before) / length(clients)
      end

    %{
      clients: length(clients),
      fill: %{fill | db: adjust(fill.db, idle.db)},
      idle: idle,
      isolated: finish_isolated(isolated, idle),
      memory_per_client: memory_per_client,
      steady: finish_steady(steady, idle)
    }
  end

  defp per_write(db, writes) do
    Map.new(db, fn
      {:at_ms, value} -> {:at_ms, value}
      {key, value} -> {key, value / writes}
    end)
  end

  # Paced from the start rather than from each write's end, so a slow write doesn't slow the rate
  # down unless it outlasts the gap.
  defp steady(peer, clients, spec, stats_before) do
    interval_ms = 1_000 / spec.rate
    count = div(spec.duration_ms * spec.rate, 1_000)
    first = @warmup_writes + @isolated_writes
    first_marker = spec.first_marker
    started_at = System.monotonic_time(:millisecond)

    cpu_before = Measure.cpu_sample(peer)

    writes =
      Map.new(0..(count - 1), fn offset ->
        due_at = started_at + round(offset * interval_ms)
        Process.sleep(max(due_at - System.monotonic_time(:millisecond), 0))

        {first_marker + first + offset, spec.write.(peer, first + offset)}
      end)

    written_ms = System.monotonic_time(:millisecond) - started_at

    Process.sleep(@drain_ms)
    cpu_after = Measure.cpu_sample(peer)
    stats_after = DB.settled_stats(spec.conn)

    {times, missing} = Measure.latencies(writes, collect(clients), spec.expected)

    raw = %{
      cpu_ms: Measure.cpu_ms(cpu_before, cpu_after),
      db: DB.stats_delta(stats_after, stats_before),
      deliveries: length(times),
      elapsed_ms: Measure.elapsed_ms(cpu_before, cpu_after),
      max_ms: Enum.max(times, fn -> nil end),
      missing: missing,
      p50_ms: Measure.percentile(times, 50),
      p95_ms: Measure.percentile(times, 95),
      p99_ms: Measure.percentile(times, 99),
      # The writes span count - 1 gaps.
      rate: if(count > 1, do: (count - 1) / (written_ms / 1_000)),
      writes: count
    }

    {raw, stats_after}
  end
end
