defmodule HologramSyncBenchmark.Seed do
  @moduledoc false

  # Writes a case's rows through Hologram on the server node, so they are stored exactly as an
  # app's writes are. Runs before any client connects, and the driver empties the log afterwards,
  # so no session ever sees these writes.

  alias Hologram.Auth
  alias Hologram.DB
  alias HologramSyncBenchmark.Entities.RoleBoard
  alias HologramSyncBenchmark.Entities.User

  # Rows per transaction. Each create inside a transaction opens two savepoints, one in the
  # Writer's deadlock retry and one in the entity's own create, and a transaction holding more than
  # PostgreSQL's 64 cached subtransactions slows every other session's visibility checks (see
  # Hologram.DB.transaction/2). Committing one row at a time makes seeding slow.
  @chunk_size 30

  @max_concurrency 8

  @doc """
  Creates the given number of cards of the given board type, positioned 0 up, and returns :ok.
  Runs on the server node.

  `values` are set on every card, like the board the cards belong to.
  """
  @spec cards(module, pos_integer, keyword) :: :ok
  def cards(card_type, count, values \\ []) do
    0..(count - 1)
    |> Stream.map(&card_type.new([position: &1, title: "card #{&1}"] ++ values))
    |> create_all()

    :ok
  end

  @doc """
  Creates one board and grants each given user the viewer role on it, returning the board's id.
  Runs on the server node, as trusted code, which may grant without holding the role.
  """
  @spec role_board([String.t()]) :: String.t()
  def role_board(user_ids) do
    board =
      [name: "board"]
      |> RoleBoard.new()
      |> DB.create!()

    user_ids
    |> Task.async_stream(&Auth.grant_role(&1, :viewer, board),
      max_concurrency: @max_concurrency,
      timeout: :infinity
    )
    |> Stream.run()

    board.id
  end

  @doc """
  Creates the given number of users and returns their ids, in the order the clients sign in as
  them. Runs on the server node.
  """
  @spec users(pos_integer) :: [String.t()]
  def users(count) do
    0..(count - 1)
    |> Stream.map(&User.new(name: "user #{&1}"))
    |> create_all()
    |> Enum.map(& &1.id)
  end

  # In the order given, so the ids line up with what they were created from.
  defp create_all(entities) do
    entities
    |> Stream.chunk_every(@chunk_size)
    |> Task.async_stream(&create_chunk/1, max_concurrency: @max_concurrency, timeout: :infinity)
    |> Enum.flat_map(fn {:ok, created} -> created end)
  end

  defp create_chunk(entities) do
    {:ok, created} = DB.transaction(fn -> Enum.map(entities, &DB.create!/1) end)

    created
  end
end
