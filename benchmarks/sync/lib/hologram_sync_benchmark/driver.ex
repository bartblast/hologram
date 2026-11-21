defmodule HologramSyncBenchmark.Driver do
  @moduledoc false

  # credo:disable-for-this-file Credo.Check.Refactor.IoPuts

  # What `mix run --no-start bench.exs` runs: parses the options, prepares the driver node and the
  # database, and runs the chosen case. The driver starts only what it needs itself - never
  # Hologram's application, which would make it a second node syncing against the same database.

  alias HologramSyncBenchmark.Cases.Access
  alias HologramSyncBenchmark.Cases.Board
  alias HologramSyncBenchmark.Cases.Deploy
  alias HologramSyncBenchmark.Cases.Lock
  alias HologramSyncBenchmark.Cases.Reconnect
  alias HologramSyncBenchmark.Cases.Tenants
  alias HologramSyncBenchmark.Client
  alias HologramSyncBenchmark.Clients
  alias HologramSyncBenchmark.DB
  alias HologramSyncBenchmark.Entities.Card
  alias HologramSyncBenchmark.Peer
  alias HologramSyncBenchmark.Probe
  alias HologramSyncBenchmark.Report
  alias HologramSyncBenchmark.Seeding
  alias HologramSyncBenchmark.Step
  alias HologramSyncBenchmark.Sweep
  alias HologramSyncBenchmark.Writer

  @board_page "HologramSyncBenchmark.BoardPage"

  @cases ~w(boot seed smoke board board_roles tenants access deploy deploy_tenants reconnect
            reconnect_tenants lock)

  # The options and their defaults: the board's size; the tenants, members per tenant and tasks
  # per tenant of the tenants case; the access case's docs and the seconds a change of access may
  # take to reach every client; the client counts a sweep steps through; the steady writes' rate
  # per second and length in seconds; the slowest p99 delivery in milliseconds a step passes
  # with; how long in seconds a client may take to fill; how long in seconds the deploy cases'
  # clients may take to all hold their pots again; how many writes the reconnect cases make while
  # their clients are away, how long in seconds those clients take to come back and how long they
  # may take to be caught up, and how many writes per second land while they do; how long in
  # seconds the lock case runs each number of writers; and the server node's memory in GB past
  # which a step is stopped, fixed rather than a share of the machine's, so a figure means the
  # same on any machine.
  @defaults [
    access_limit: 10,
    cards: 2_000,
    docs: 5_000,
    duration: 30,
    fill_timeout: 300,
    gap_writes: 100,
    lock_duration: 10,
    members: 5,
    memory_limit: 4,
    p99_limit: 1_000,
    rate: 2,
    refill_limit: 60,
    tasks: 100,
    tenants: 20,
    wave_limit: 120,
    wave_spread: 5,
    wave_writes: 0
  ]

  # How long in milliseconds the boot check runs the probe.
  @boot_probe_ms 1_000

  @default_smoke_clients 10

  # How many writes the smoke check makes while its clients are away, and how long in milliseconds
  # the clients take to come back.
  @smoke_gap_writes 5

  @smoke_return_spread_ms 200

  @switches [
    access_limit: :integer,
    cards: :integer,
    docs: :integer,
    case: :string,
    clients: :string,
    duration: :integer,
    fill_timeout: :integer,
    gap_writes: :integer,
    lock_duration: :integer,
    members: :integer,
    memory_limit: :integer,
    p99_limit: :integer,
    rate: :integer,
    refill_limit: :integer,
    tasks: :integer,
    tenants: :integer,
    wave_limit: :integer,
    wave_spread: :integer,
    wave_writes: :integer
  ]

  @doc """
  Runs the benchmark with the given command line arguments and returns :ok.
  """
  @spec main([String.t()]) :: :ok
  def main(argv) do
    # Checked here, though it matters earlier: without it the compile that ran before this script
    # skipped the Hologram compiler, so the server node would have no bundle and no page types.
    if System.get_env("HOLOGRAM_START") != "1" do
      raise "run with HOLOGRAM_START=1, see README.md"
    end

    # Hologram boots with its application, so a run without --no-start has already made this node
    # a second one syncing against the benchmark's database. On a database with no owner yet, that
    # boot also claimed it for the driver's env, which the server node's env then refuses.
    if List.keymember?(Application.started_applications(), :hologram, 0) do
      raise "run with --no-start, see README.md, and drop the benchmark's database if a run " <>
              "without it was the first to use it"
    end

    opts = parse_options!(argv)

    {:ok, _apps} = Application.ensure_all_started([:inets, :jason, :mint, :postgrex])
    :ok = Peer.start_distribution!()
    :ok = Peer.ensure_database!()

    run_case(opts[:case], opts)
  end

  defp parse_options!(argv) do
    case OptionParser.parse(argv, strict: @switches) do
      {opts, [], []} ->
        @defaults
        |> Keyword.merge(opts)
        |> Keyword.update(:clients, nil, &parse_counts!/1)
        |> validate_options!()

      {_opts, args, invalid} ->
        raise ArgumentError, "unknown arguments: #{inspect(args ++ invalid)}"
    end
  end

  defp validate_options!(opts) do
    if opts[:case] not in @cases do
      raise ArgumentError, "--case must be one of: #{Enum.join(@cases, ", ")}"
    end

    for {key, value} <- opts, key != :wave_writes, is_integer(value), value < 1 do
      raise ArgumentError, "--#{String.replace(to_string(key), "_", "-")} must be at least 1"
    end

    if opts[:wave_writes] < 0 do
      raise ArgumentError, "--wave-writes can't be negative"
    end

    writes = Step.writes(opts[:rate], opts[:duration])

    if writes >= Sweep.markers_per_step() do
      raise ArgumentError, "a step makes #{writes} writes, more than it has markers for"
    end

    opts
  end

  defp parse_count!(text) do
    text
    |> String.trim()
    |> String.to_integer()
  end

  defp parse_counts!(text) do
    counts =
      text
      |> String.split(",", trim: true)
      |> Enum.map(&parse_count!/1)

    if counts == [] or Enum.any?(counts, &(&1 < 1)) do
      raise ArgumentError, "--clients takes client counts of at least 1, like 1,10,100"
    end

    Sweep.sort_counts(counts)
  end

  # Boots a server node, renders a page on it and stops it - the check that the app, its database,
  # its schema and the build the node serves come up, before any case depends on them.
  defp run_case("boot", _opts) do
    Peer.with_peer(&check_boot/1)
  end

  # Resets the database and seeds the board, printing what seeding cost the database - the check
  # that a case can start from a known state, and that the counters move.
  defp run_case("seed", opts) do
    conn = DB.connect!()
    count = opts[:cards]

    {seeding, _extra} = Seeding.board!(conn, Card, count)

    IO.puts("Seeded #{count} cards")
    IO.puts("Seeding cost #{inspect(seeding)}")
  end

  # Connects anonymous clients to a seeded board and prints how long each took to hold every
  # card, then has them leave, makes a few writes and has them come back, printing what each was
  # sent - the check that clients connect, sync, report and catch up from where they were.
  defp run_case("smoke", opts) do
    conn = DB.connect!()
    count = hd(opts[:clients] || [@default_smoke_clients])

    :ok = Clients.check_limits!(count, Step.connect_concurrency())
    _seeded = Seeding.board!(conn, Card, opts[:cards])

    Peer.with_peer(fn peer ->
      ids = Peer.rpc(peer, Writer, :ids, [Card])
      :ok = Peer.rpc(peer, Writer, :warm_up, [Card, elem(ids, 0), :title, "warm-up"])

      clients = start_clients(peer, count, "/session", @board_page)

      Clients.prepare_all!(clients, Step.connect_concurrency())
      failures = Clients.connect_all(clients, Step.connect_concurrency())
      reports = Clients.await_fills(clients, opts[:fill_timeout] * 1_000)

      print_fills(reports, failures)

      smoke_return(peer, clients, ids, opts)

      Clients.close_all(clients)
    end)
  end

  defp run_case("board", opts), do: run_sweep(opts, Board.sweep_case(opts, :plain))

  defp run_case("board_roles", opts), do: run_sweep(opts, Board.sweep_case(opts, :roles))

  defp run_case("tenants", opts), do: run_sweep(opts, Tenants.sweep_case(opts))

  defp run_case("access", opts), do: run_sweep(opts, Access.sweep_case(opts))

  defp run_case("deploy", opts), do: run_sweep(opts, Deploy.sweep_case(opts, :board))

  defp run_case("deploy_tenants", opts), do: run_sweep(opts, Deploy.sweep_case(opts, :tenants))

  defp run_case("reconnect", opts), do: run_sweep(opts, Reconnect.sweep_case(opts, :board))

  defp run_case("reconnect_tenants", opts) do
    run_sweep(opts, Reconnect.sweep_case(opts, :tenants))
  end

  # Writers rather than clients: --clients gives how many write at once.
  defp run_case("lock", opts), do: Lock.run(DB.connect!(), opts)

  # A case with clients and writes: seeds what it needs, sweeps the client counts, and writes the
  # figures into the README.
  defp run_sweep(opts, sweep_case) do
    conn = DB.connect!()
    counts = opts[:clients] || sweep_case.counts

    :ok = sweep_case.check!.(counts)

    # A case connecting its clients all at once overflows the listen backlog sooner.
    burst_of = Map.get(sweep_case, :burst, fn _counts -> Step.connect_concurrency() end)
    burst = burst_of.(counts)
    most = Enum.max(counts)
    :ok = Clients.check_limits!(most, burst)

    :ok = Report.check_readme!()
    run_line = Report.run_line(conn)

    context = sweep_case.seed.(conn, Enum.max(counts))

    # A case with writes at a rate gives a spec for HologramSyncBenchmark.Step; one measuring
    # something else gives its own step, pass rule, step line and tables.
    step =
      Map.get_lazy(sweep_case, :step, fn ->
        fn conn, peer, count, first_marker, context ->
          Step.run(peer, sweep_case.spec.(conn, count, first_marker, context))
        end
      end)

    memory_limit = opts[:memory_limit] * 1_073_741_824

    {results, stopped} =
      Sweep.run(
        conn,
        counts,
        # A case preparing each step on a node of its own hands the step what it prepared.
        &step.(conn, &1, &2, &3, &4 || context),
        Map.get(sweep_case, :passed?, &passed?(&1, opts)),
        Map.get(sweep_case, :summary, &Sweep.summary/1),
        memory_limit,
        sweep_hooks(sweep_case, conn, context)
      )

    why = Map.get(sweep_case, :why, &why_failed(&1, opts))
    figure = Sweep.figure(results, stopped, opts[:memory_limit], why)
    IO.puts("Clients per node, #{sweep_case.title}: #{figure}")

    options =
      sweep_case.options ++
        [
          "#{sweep_case.clients}, steps of #{Enum.join(counts, ", ")} " <>
            if(counts == [1], do: "client", else: "clients"),
          "a step stops, and the sweep with it, when the server node's memory passes " <>
            "#{opts[:memory_limit]} GB"
        ] ++ Map.get(sweep_case, :step_options, write_options(opts))

    :ok =
      Report.write_case!(
        sweep_case.name,
        sweep_case.title,
        run_line,
        options,
        figure,
        Map.get(sweep_case, :tables, &step_tables/1).(results)
      )
  end

  defp sweep_hooks(%{before_step: before_step, after_step: after_step}, conn, context) do
    [
      after_step: after_step,
      before_step: &before_step.(conn, &1, &2, &3, context)
    ]
  end

  defp sweep_hooks(_sweep_case, _conn, _context), do: []

  defp write_options(opts) do
    [
      "steady writes at #{opts[:rate]} per second for #{opts[:duration]} s",
      "a step passes when every client fills within #{opts[:fill_timeout]} s and every " <>
        "write reaches every client it should and no other, with the steady writes' p99 within " <>
        "#{opts[:p99_limit]} ms"
    ]
  end

  defp step_tables(results) do
    [
      {"Fill", Report.fill_columns(), Enum.map(results, &Report.fill_row/1)},
      {"Single writes, median of 5", Report.isolated_columns(),
       Enum.map(results, &Report.isolated_row/1)},
      {"Steady writes", Report.steady_columns(), Enum.map(results, &Report.steady_row/1)}
    ]
  end

  # Every client filled in time, every write reached every client it should have and no other,
  # each warm-up and single write within the wait, no session was cut, and the steady writes' p99
  # stayed within the limit. A session cut after the last write it should have had misses
  # nothing, so the cuts count on their own.
  defp passed?(result, opts) do
    filled?(result.fill, opts) and result.warmup_cut_short == 0 and
      result.isolated.cut_short == 0 and result.isolated.leaked == 0 and
      result.session_cuts == 0 and delivered?(result.steady, opts)
  end

  # What failed a step with writes, for the figure's note.
  defp why_failed(result, opts) do
    %{fill: fill, steady: steady} = result

    [
      Sweep.fill_reasons(fill, opts[:fill_timeout]),
      waited_reasons(result),
      steady.missing > 0 && count_of(steady.missing, "delivery", "deliveries") <> " missing",
      steady.leaked > 0 && "#{steady.leaked} deliveries leaked",
      steady.streams_lost > 0 && count_of(steady.streams_lost, "stream", "streams") <> " lost",
      result.session_cuts > 0 && count_of(result.session_cuts, "session", "sessions") <> " cut",
      (steady.p99_ms != nil and steady.p99_ms > opts[:p99_limit]) &&
        "steady p99 #{round(steady.p99_ms)} ms"
    ]
    |> List.flatten()
    |> Enum.filter(& &1)
    |> Enum.join(", ")
  end

  # The writes each waited on until it reached everyone: the warm-up and the single writes.
  defp waited_reasons(%{isolated: isolated, warmup_cut_short: warmup_cut_short}) do
    [
      warmup_cut_short > 0 && "#{warmup_cut_short} warm-up writes never reached everyone",
      isolated.cut_short > 0 && "#{isolated.cut_short} single writes never reached everyone",
      isolated.leaked > 0 &&
        count_of(isolated.leaked, "single write delivery", "single write deliveries") <> " leaked"
    ]
  end

  defp count_of(1, one, _many), do: "1 #{one}"

  defp count_of(count, _one, many), do: "#{count} #{many}"

  defp delivered?(steady, opts) do
    steady.missing == 0 and steady.leaked == 0 and steady.streams_lost == 0 and
      steady.p99_ms != nil and steady.p99_ms <= opts[:p99_limit]
  end

  defp filled?(fill, opts) do
    fill.failed == 0 and fill.unfinished == 0 and fill.connect_failures == 0 and
      Enum.all?(fill.ms, &(&1 <= opts[:fill_timeout] * 1_000))
  end

  defp print_fills(reports, failures) do
    for {report, index} <- Enum.with_index(reports, 1) do
      fill =
        if report.synced_all_at do
          "#{div(report.synced_all_at - report.connected_at, 1_000)} ms"
        else
          "no fill"
        end

      IO.puts(
        "Client #{index}: #{fill}, #{report.bytes} bytes, #{report.connect_retries} retries" <>
          if(report.failure, do: ", failed: #{inspect(report.failure)}", else: "")
      )
    end

    IO.puts("#{length(failures)} clients failed to connect")
  end

  defp smoke_return(peer, clients, ids, opts) do
    left_out = Clients.leave_all(clients)
    numbers = Enum.to_list(0..(min(@smoke_gap_writes, tuple_size(ids)) - 1))

    for number <- numbers do
      Peer.rpc(peer, Writer, :update, [Card, elem(ids, number), :title, Client.marker(number)])
    end

    # Numbered among all the clients, so a line names the same client as its fill's line above.
    {returning, indexes} =
      clients
      |> Enum.with_index(1)
      |> Enum.reject(fn {client, _index} -> List.keymember?(left_out, client, 0) end)
      |> Enum.unzip()

    :ok = Clients.come_back_all(returning, @smoke_return_spread_ms)

    returning
    |> Clients.await_caught_up(opts[:fill_timeout] * 1_000)
    |> Enum.zip(indexes)
    |> print_returns(numbers)

    IO.puts("#{length(left_out)} clients couldn't leave")
  end

  defp print_returns(indexed_reports, numbers) do
    for {report, index} <- indexed_reports do
      back =
        if report.caught_up_at do
          "#{div(report.caught_up_at - report.returned_at, 1_000)} ms"
        else
          "not caught up"
        end

      got = Enum.count(numbers, &Map.has_key?(report.markers, &1))

      IO.puts(
        "Client #{index} back: #{back}, #{report.bytes - report.bytes_at_leave} bytes, " <>
          "#{got}/#{length(numbers)} gap writes, #{report.return_restarts} restarts" <>
          if(report.failure, do: ", failed: #{inspect(report.failure)}", else: "")
      )
    end
  end

  defp start_clients(peer, count, cookie_path, page) do
    peer
    |> Clients.base_opts(page)
    |> Keyword.put(:cookie_path, cookie_path)
    |> List.duplicate(count)
    |> Clients.start_all()
  end

  defp check_boot(peer) do
    model_hash = Peer.rpc(peer, Hologram.Entity.Model, :hash, [])
    IO.puts("Server node #{peer.node} is up at #{Peer.base_url(peer)}, model hash #{model_hash}")

    url = ~c"#{Peer.base_url(peer)}/sign_in/#{UUID.uuid4()}"
    {:ok, {{_version, 200, _reason}, headers, _body}} = :httpc.request(:get, {url, []}, [], [])

    if not List.keymember?(headers, ~c"set-cookie", 0) do
      raise "the sign-in page set no session cookie"
    end

    IO.puts("It renders pages and signs clients in")

    started_at = System.monotonic_time(:millisecond)

    probe =
      peer
      |> Peer.base_url()
      |> Probe.start()

    Process.sleep(@boot_probe_ms)

    figures =
      probe
      |> Probe.stop()
      |> Probe.summary(started_at, System.monotonic_time(:millisecond))

    if figures.requests == 0 or figures.failures > 0 do
      raise "the probe page didn't answer: #{inspect(figures)}"
    end

    IO.puts(
      "The probe made #{figures.requests} requests, p50 #{Report.cell(figures.p50_ms)} ms, " <>
        "p99 #{Report.cell(figures.p99_ms)} ms"
    )
  end
end
