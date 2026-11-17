defmodule HologramSyncBenchmark.Seeding do
  @moduledoc false

  # Seeding a case, driver side: the database emptied, the rows written on a server node of their
  # own, the log emptied and the database vacuumed after, and the rows counted to check they're
  # all there.

  alias HologramSyncBenchmark.DB
  alias HologramSyncBenchmark.Peer
  alias HologramSyncBenchmark.Seed

  @doc """
  Empties the database, seeds the given number of cards of the given type, and returns what
  seeding cost the database and what the given function returned.

  `prepare` runs first on the server node, for whatever the cards and the clients need, and
  returns the values every card gets and what the case wants back.
  """
  @spec board!(pid, module, pos_integer, (Peer.t() -> {keyword, term})) :: {DB.stats(), term}
  def board!(conn, card_type, count, prepare \\ fn _peer -> {[], nil} end) do
    {seeding, {table, extra}} =
      seed!(conn, fn peer ->
        {card_values, extra} = prepare.(peer)
        :ok = Peer.rpc(peer, Seed, :cards, [card_type, count, card_values])

        {table_name(peer, card_type), extra}
      end)

    :ok = check_rows!(conn, table, count)

    {seeding, extra}
  end

  @doc """
  Raises when the given entity table holds another number of rows than the given one, and
  returns :ok.
  """
  @spec check_rows!(pid, String.t(), non_neg_integer) :: :ok
  def check_rows!(conn, table, expected) do
    stored = DB.row_count(conn, table)

    if stored != expected do
      raise "seeding stored #{stored} rows in #{table}, not #{expected}"
    end

    :ok
  end

  @doc """
  Empties the database, runs the given function on a server node to seed it, and returns what
  seeding cost the database and what the function returned.

  Read inside the server node's life, after its boot, so the figure leaves out its connects and
  the schema check. It still holds the idle node's dispatcher polls over the settle.
  """
  @spec seed!(pid, (Peer.t() -> result)) :: {DB.stats(), result} when result: term
  def seed!(conn, fun) do
    :ok = DB.reset!(conn)

    result =
      Peer.with_peer(fn peer ->
        :ok = DB.disable_autovacuum!(conn)

        before = DB.settled_stats(conn)
        result = fun.(peer)

        seeding =
          conn
          |> DB.settled_stats()
          |> DB.stats_delta(before)

        {seeding, result}
      end)

    :ok = DB.truncate_log!(conn)
    :ok = DB.vacuum_analyze!(conn)

    result
  end

  @doc """
  Returns the name of the given entity type's table, read on the server node.
  """
  @spec table_name(Peer.t(), module) :: String.t()
  def table_name(peer, entity_type), do: Peer.rpc(peer, Hologram.DB, :table_name, [entity_type])
end
