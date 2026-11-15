defmodule HologramSyncBenchmark.Driver do
  @moduledoc false

  # credo:disable-for-this-file Credo.Check.Refactor.IoPuts

  # What `mix run --no-start bench.exs` runs: parses the options, prepares the driver node and the
  # database, and runs the chosen case. The driver starts only what it needs itself - never
  # Hologram's application, which would make it a second node syncing against the same database.

  alias HologramSyncBenchmark.Client
  alias HologramSyncBenchmark.Clients
  alias HologramSyncBenchmark.DB
  alias HologramSyncBenchmark.Entities.Card
  alias HologramSyncBenchmark.Entities.RoleCard
  alias HologramSyncBenchmark.Peer
  alias HologramSyncBenchmark.Report
  alias HologramSyncBenchmark.Seed
  alias HologramSyncBenchmark.Step
  alias HologramSyncBenchmark.Sweep
  alias HologramSyncBenchmark.Writer

  @board_page "HologramSyncBenchmark.BoardPage"

  @role_board_page "HologramSyncBenchmark.RoleBoardPage"

  @board_sweep [1, 2, 5, 10, 20, 50, 100, 200, 500, 1_000, 2_000, 5_000]

  @cases ~w(boot seed smoke board board_roles)

  # The options and their defaults: the board's size, the client counts a sweep steps through,
  # the steady writes' rate per second and length in seconds, the slowest p99 delivery in
  # milliseconds a step passes with, and how long in seconds a client may take to fill.
  @defaults [
    cards: 2_000,
    duration: 30,
    fill_timeout: 300,
    p99_limit: 1_000,
    rate: 2
  ]

  @default_smoke_clients 10

  @switches [
    cards: :integer,
    case: :string,
    clients: :string,
    duration: :integer,
    fill_timeout: :integer,
    p99_limit: :integer,
    rate: :integer
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

    # Each timed write in a step goes to a row of its own: rounds merge, and a patch carries the
    # row's current value, so two writes to one row in one round would lose the first marker.
    writes = Step.writes(opts[:rate], opts[:duration])

    if writes > opts[:cards] do
      raise ArgumentError,
            "a step makes #{writes} writes, more than the #{opts[:cards]} cards they go to"
    end

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

    {seeding, _extra} = seed!(conn, Card, count)

    IO.puts("Seeded #{count} cards")
    IO.puts("Seeding cost #{inspect(seeding)}")
  end

  # Connects anonymous clients to a seeded board and prints how long each took to hold every
  # card - the check that clients connect, sync and report.
  defp run_case("smoke", opts) do
    conn = DB.connect!()
    count = hd(opts[:clients] || [@default_smoke_clients])

    :ok = Clients.check_limits!(count, Step.connect_concurrency())
    _seeded = seed!(conn, Card, opts[:cards])

    Peer.with_peer(fn peer ->
      clients = start_clients(peer, count, "/board", @board_page)

      [] = Clients.prepare_all(clients, Step.connect_concurrency())
      failures = Clients.connect_all(clients, Step.connect_concurrency())
      reports = Clients.await_fills(clients, opts[:fill_timeout] * 1_000)

      Clients.close_all(clients)

      print_fills(reports, failures)
    end)
  end

  # A shared board: every client sees every card, and every write reaches every client.
  defp run_case("board", opts) do
    run_board(opts, %{
      card_type: Card,
      clients: "anonymous clients",
      name: "board",
      page: @board_page,
      prepare: fn _peer, count -> {[], List.duplicate("/board", count)} end,
      rule: "a bare `allow :read`",
      title: "Shared board"
    })
  end

  # A board whose cards are read through a role: each client signs in as a user of its own who
  # holds the viewer role on the one board the cards belong to. Every client still reads every
  # card, but every rule check reads the card's board and asks for the user's grants on it.
  defp run_case("board_roles", opts) do
    run_board(opts, %{
      card_type: RoleCard,
      clients: "signed-in clients, each user holding the viewer role on the board",
      name: "board_roles",
      page: @role_board_page,
      prepare: fn peer, count ->
        user_ids = Peer.rpc(peer, Seed, :users, [count])
        board_id = Peer.rpc(peer, Seed, :role_board, [user_ids])

        {[board_id: board_id], Enum.map(user_ids, &"/sign_in/#{&1}")}
      end,
      rule:
        "`allow :read, via: {:read, board}` on cards and `allow :read, to: :viewer` on the board",
      title: "Shared board read by role"
    })
  end

  # A board case: seeds the cards and whatever its clients need, sweeps the client counts, and
  # writes the figures into the README. `prepare` seeds what the cards and the clients need for
  # the given number of clients, on the server node, and returns the values every card gets and
  # the path each client gets its session cookie from.
  defp run_board(opts, board) do
    conn = DB.connect!()
    counts = opts[:clients] || @board_sweep

    :ok =
      counts
      |> Enum.max()
      |> Clients.check_limits!(Step.connect_concurrency())

    :ok = Report.check_readme!()
    run_line = Report.run_line(conn)

    {_seeding, cookie_paths} =
      seed!(conn, board.card_type, opts[:cards], &board.prepare.(&1, Enum.max(counts)))

    results =
      Sweep.run(
        conn,
        counts,
        fn peer, count, first_marker ->
          spec = board_spec(conn, count, first_marker, opts, board, cookie_paths)
          Step.run(peer, spec)
        end,
        &passed?(&1, opts)
      )

    figure = Sweep.figure(results)
    IO.puts("Clients per node, #{board.title}: #{figure}")

    options = [
      "#{opts[:cards]} cards read with #{board.rule}, which lets every client read every card, " <>
        "so every write reaches every client",
      "#{board.clients}, steps of #{Enum.join(counts, ", ")} " <>
        if(counts == [1], do: "client", else: "clients"),
      "steady writes at #{opts[:rate]} per second for #{opts[:duration]} s",
      "a step passes when every client fills within #{opts[:fill_timeout]} s and every write " <>
        "reaches every client, with the steady writes' p99 within #{opts[:p99_limit]} ms"
    ]

    :ok =
      Report.write_case!(
        board.name,
        board.title,
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

  defp board_spec(conn, count, first_marker, opts, board, cookie_paths) do
    every_client = Enum.to_list(0..(count - 1))

    %{
      client_opts: fn peer ->
        base = client_opts(peer, nil, board.page)

        cookie_paths
        |> Enum.take(count)
        |> Enum.map(&Keyword.put(base, :cookie_path, &1))
      end,
      conn: conn,
      duration_ms: opts[:duration] * 1_000,
      expected: fn _number -> every_client end,
      fill_timeout_ms: opts[:fill_timeout] * 1_000,
      first_marker: first_marker,
      rate: opts[:rate],
      rows: &Peer.rpc(&1, Writer, :ids, [board.card_type]),
      write: fn peer, ids, offset, marker ->
        args = [board.card_type, elem(ids, offset), :title, Client.marker(marker)]
        Peer.rpc(peer, Writer, :update, args)
      end
    }
  end

  # The greeting names the server's model hash and protocol version, read from the server node,
  # since the driver never boots Hologram.
  defp client_opts(peer, cookie_path, page) do
    [
      base_url: Peer.base_url(peer),
      cookie_path: cookie_path,
      model_hash: Peer.rpc(peer, Hologram.Entity.Model, :hash, []),
      page: page,
      protocol_version: Peer.rpc(peer, Hologram.Sync.Frame, :protocol_version, [])
    ]
  end

  # Every client filled in time, every write reached every client it should have, each single
  # write within the wait, and the steady writes' p99 stayed within the limit.
  defp passed?(result, opts) do
    %{fill: fill, isolated: isolated, steady: steady} = result

    fill.failed == 0 and fill.unfinished == 0 and fill.connect_failures == 0 and
      Enum.all?(fill.ms, &(&1 <= opts[:fill_timeout] * 1_000)) and isolated.cut_short == 0 and
      steady.missing == 0 and steady.streams_lost == 0 and steady.p99_ms != nil and
      steady.p99_ms <= opts[:p99_limit]
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

  # Empties the database, runs the given function on the server node for whatever the cards and
  # the clients need, and seeds the given number of cards of the given type with the values it
  # returned, returning what seeding cost the database and what else the function returned. Read
  # inside the server node's life, after its boot, so the figure leaves out its connects and the
  # schema check. It still holds the idle node's dispatcher polls over the settle.
  defp seed!(conn, card_type, count, prepare \\ fn _peer -> {[], nil} end) do
    :ok = DB.reset!(conn)

    {table, seeding, extra} =
      Peer.with_peer(fn peer ->
        :ok = DB.disable_autovacuum!(conn)

        before = DB.settled_stats(conn)
        {card_values, extra} = prepare.(peer)
        :ok = Peer.rpc(peer, Seed, :cards, [card_type, count, card_values])

        seeding =
          conn
          |> DB.settled_stats()
          |> DB.stats_delta(before)

        {Peer.rpc(peer, Hologram.DB, :table_name, [card_type]), seeding, extra}
      end)

    :ok = DB.truncate_log!(conn)
    :ok = DB.vacuum_analyze!(conn)

    stored = DB.row_count(conn, table)

    if stored != count do
      raise "seeding stored #{stored} cards, not #{count}"
    end

    {seeding, extra}
  end

  defp start_clients(peer, count, cookie_path, page) do
    peer
    |> client_opts(cookie_path, page)
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
