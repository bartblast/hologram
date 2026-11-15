defmodule HologramSyncBenchmark.Driver do
  @moduledoc false

  # credo:disable-for-this-file Credo.Check.Refactor.IoPuts

  # What `mix run --no-start bench.exs` runs: parses the options, prepares the driver node and the
  # database, and runs the chosen case. The driver starts only what it needs itself - never
  # Hologram's application, which would make it a second node syncing against the same database.

  alias HologramSyncBenchmark.Cases.Board
  alias HologramSyncBenchmark.Cases.Tenants
  alias HologramSyncBenchmark.Clients
  alias HologramSyncBenchmark.DB
  alias HologramSyncBenchmark.Entities.Card
  alias HologramSyncBenchmark.Peer
  alias HologramSyncBenchmark.Report
  alias HologramSyncBenchmark.Seeding
  alias HologramSyncBenchmark.Step
  alias HologramSyncBenchmark.Sweep

  @board_page "HologramSyncBenchmark.BoardPage"

  @cases ~w(boot seed smoke board board_roles tenants)

  # The options and their defaults: the board's size; the tenants, members per tenant and tasks
  # per tenant of the tenants case; the client counts a sweep steps through; the steady writes'
  # rate per second and length in seconds; the slowest p99 delivery in milliseconds a step passes
  # with; and how long in seconds a client may take to fill.
  @defaults [
    cards: 2_000,
    duration: 30,
    fill_timeout: 300,
    members: 5,
    p99_limit: 1_000,
    rate: 2,
    tasks: 100,
    tenants: 20
  ]

  @default_smoke_clients 10

  @switches [
    cards: :integer,
    case: :string,
    clients: :string,
    duration: :integer,
    fill_timeout: :integer,
    members: :integer,
    p99_limit: :integer,
    rate: :integer,
    tasks: :integer,
    tenants: :integer
  ]

  @doc """
  Runs the benchmark with the given command line arguments and returns :ok.
  """
  @spec main([String.t()]) :: :ok
  def main(argv) do
    # Checked here, though it matters earlier: without it the compile that ran before this script
    # skipped the Hologram compiler, so the server node would have no bundle and no windows.
    if System.get_env("HOLOGRAM_START") != "1" do
      raise "run with HOLOGRAM_START=1, see README.md"
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

    for {key, value} <- opts, is_integer(value), value < 1 do
      raise ArgumentError, "--#{key} must be at least 1"
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
  # card - the check that clients connect, sync and report.
  defp run_case("smoke", opts) do
    conn = DB.connect!()
    count = hd(opts[:clients] || [@default_smoke_clients])

    :ok = Clients.check_limits!(count, Step.connect_concurrency())
    _seeded = Seeding.board!(conn, Card, opts[:cards])

    Peer.with_peer(fn peer ->
      clients = start_clients(peer, count, "/board", @board_page)

      [] = Clients.prepare_all(clients, Step.connect_concurrency())
      failures = Clients.connect_all(clients, Step.connect_concurrency())
      reports = Clients.await_fills(clients, opts[:fill_timeout] * 1_000)

      Clients.close_all(clients)

      print_fills(reports, failures)
    end)
  end

  defp run_case("board", opts), do: run_sweep(opts, Board.sweep_case(opts, :plain))

  defp run_case("board_roles", opts), do: run_sweep(opts, Board.sweep_case(opts, :roles))

  defp run_case("tenants", opts), do: run_sweep(opts, Tenants.sweep_case(opts))

  # A case with clients and writes: seeds what it needs, sweeps the client counts, and writes the
  # figures into the README.
  defp run_sweep(opts, sweep_case) do
    conn = DB.connect!()
    counts = opts[:clients] || sweep_case.counts

    :ok = sweep_case.check!.(counts)

    :ok =
      counts
      |> Enum.max()
      |> Clients.check_limits!(Step.connect_concurrency())

    :ok = Report.check_readme!()
    run_line = Report.run_line(conn)

    context = sweep_case.seed.(conn, Enum.max(counts))

    results =
      Sweep.run(
        conn,
        counts,
        fn peer, count, first_marker ->
          Step.run(peer, sweep_case.spec.(conn, count, first_marker, context))
        end,
        &passed?(&1, opts)
      )

    figure = Sweep.figure(results)
    IO.puts("Clients per node, #{sweep_case.title}: #{figure}")

    options =
      sweep_case.options ++
        [
          "#{sweep_case.clients}, steps of #{Enum.join(counts, ", ")} " <>
            if(counts == [1], do: "client", else: "clients"),
          "steady writes at #{opts[:rate]} per second for #{opts[:duration]} s",
          "a step passes when every client fills within #{opts[:fill_timeout]} s and every " <>
            "write reaches every client it should and no other, with the steady writes' p99 within " <>
            "#{opts[:p99_limit]} ms"
        ]

    :ok =
      Report.write_case!(
        sweep_case.name,
        sweep_case.title,
        run_line,
        options,
        figure,
        step_tables(results)
      )
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
  # each single write within the wait, and the steady writes' p99 stayed within the limit.
  defp passed?(result, opts) do
    filled?(result.fill, opts) and result.isolated.cut_short == 0 and
      delivered?(result.steady, opts)
  end

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
  end
end
