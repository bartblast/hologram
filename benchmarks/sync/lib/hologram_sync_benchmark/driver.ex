defmodule HologramSyncBenchmark.Driver do
  @moduledoc false

  # credo:disable-for-this-file Credo.Check.Refactor.IoPuts

  # What `mix run --no-start bench.exs` runs: parses the options, prepares the driver node and the
  # database, and runs the chosen case. The driver starts only what it needs itself - never
  # Hologram's application, which would make it a second node syncing against the same database.

  alias HologramSyncBenchmark.DB
  alias HologramSyncBenchmark.Entities.Card
  alias HologramSyncBenchmark.Peer
  alias HologramSyncBenchmark.Seed

  @cases ~w(boot seed)

  @default_cards 2_000

  @switches [cards: :integer, case: :string]

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
        validate_options!(opts)

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

    opts
  end

  # Boots a server node, renders a page on it and stops it - the check that the app, its database,
  # its schema and the build the node serves come up, before any case depends on them.
  defp run_case("boot", _opts) do
    Peer.with_peer(&check_boot/1)
  end

  # Resets the database and seeds the board, printing what seeding cost the database - the check
  # that a case can start from a known state, and that the counters move. Read inside the server
  # node's life, after its boot, so the figure leaves out its connects and the schema check. It
  # still holds the idle node's dispatcher polls over the settle.
  defp run_case("seed", opts) do
    conn = DB.connect!()
    count = Keyword.get(opts, :cards, @default_cards)

    :ok = DB.reset!(conn)

    {table, seeding} =
      Peer.with_peer(fn peer ->
        before = DB.settled_stats(conn)
        :ok = Peer.rpc(peer, Seed, :cards, [count])

        seeding =
          conn
          |> DB.settled_stats()
          |> DB.stats_delta(before)

        {Peer.rpc(peer, Hologram.DB, :table_name, [Card]), seeding}
      end)

    :ok = DB.truncate_log!(conn)
    :ok = DB.vacuum_analyze!(conn)

    stored = DB.row_count(conn, table)

    if stored != count do
      raise "seeding stored #{stored} cards, not #{count}"
    end

    IO.puts("Seeded #{stored} cards")
    IO.puts("Seeding cost #{inspect(seeding)}")
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
