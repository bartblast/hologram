defmodule HologramSyncBenchmark.Seed do
  @moduledoc false

  # Writes a case's rows through Hologram on the server node, so they are stored exactly as an
  # app's writes are. Runs before any client connects, and the driver empties the log afterwards,
  # so no session ever sees these writes.

  alias Hologram.DB
  alias HologramSyncBenchmark.Entities.Card

  # Rows per transaction. Each create inside a transaction opens two savepoints, one in the
  # Writer's deadlock retry and one in the entity's own create, and a transaction holding more than
  # PostgreSQL's 64 cached subtransactions slows every other session's visibility checks (see
  # Hologram.DB.transaction/2). Committing one row at a time makes seeding slow.
  @chunk_size 30

  @max_concurrency 8

  @doc """
  Creates the given number of cards on the board, positioned 0 up, and returns :ok. Runs on the
  server node.
  """
  @spec cards(pos_integer) :: :ok
  def cards(count) do
    0..(count - 1)
    |> Stream.map(&Card.new(position: &1, title: "card #{&1}"))
    |> create_all()
  end

  defp create_all(entities) do
    entities
    |> Stream.chunk_every(@chunk_size)
    |> Task.async_stream(&create_chunk/1, max_concurrency: @max_concurrency, timeout: :infinity)
    |> Stream.run()
  end

  defp create_chunk(entities) do
    {:ok, _created} = DB.transaction(fn -> Enum.map(entities, &DB.create!/1) end)
  end
end
