defmodule HologramSyncBenchmark.Writer do
  @moduledoc false

  # A timed write, run on the server node the way an action's write runs there: read the row,
  # change it, write it back through the Writer, which logs the effect and notifies the nodes in
  # the same transaction.

  use Hologram.DB

  alias Hologram.DB
  alias Hologram.DB.Connection
  alias Hologram.DB.Oplog

  # How long a transaction elsewhere on the database server may hold the log's edge back.
  @warm_up_wait_ms 30_000

  @warm_up_poll_ms 10

  @doc """
  Returns the ids of the given entity type's rows in the order of their position, for a step to
  read once and untimed, so a timed write finds its row by id. Runs on the server node.
  """
  @spec ids(module) :: tuple
  def ids(entity_type) do
    table = DB.table_name(entity_type)

    ~s(SELECT "id" FROM "#{DB.schema_name()}"."#{table}" ORDER BY "position")
    |> DB.sql!()
    |> Map.fetch!(:rows)
    |> Enum.map(&hd/1)
    |> List.to_tuple()
  end

  @doc """
  Sets the given attribute of the given entity's row with the given id to the given value, and
  returns when the write returned, as `:os.system_time(:microsecond)`. Runs on the server node.

  The row is read by id first, as an action reads what it changes, which is one primary key
  lookup. Taken after the write returns, so it's an upper bound on the commit, and every delivery
  time measured from it is a lower bound by the same few microseconds.
  """
  @spec update(module, term, atom, term) :: integer
  def update(entity_type, id, attribute, value) do
    entity_type
    |> filter(id == ^id)
    |> one()
    |> DB.read()
    |> put_attribute(attribute, value)
    |> DB.update!()

    :os.system_time(:microsecond)
  end

  @doc """
  Sets the given attribute of the given entity's row with the given id to the given value, waits
  until no transaction older than that write still runs, and returns :ok. Runs on the server node.

  For before a step's clients fill. A returning client's place below the log's oldest change reads
  as one from before the log, and it's sent everything again, so the log needs a change first. The
  edge a fill's place is read from counts every transaction on the database server, so the write
  alone doesn't put the place above it (#1763).
  """
  @spec warm_up(module, term, atom, term) :: :ok
  def warm_up(entity_type, id, attribute, value) do
    {:ok, xid} =
      DB.transaction(fn ->
        _committed_at = update(entity_type, id, attribute, value)
        {:ok, %{rows: [[xid]]}} = Connection.query("SELECT pg_current_xact_id()::text", [])

        String.to_integer(xid)
      end)

    await_edge_past(xid, System.monotonic_time(:millisecond) + @warm_up_wait_ms)
  end

  defp await_edge_past(xid, deadline) do
    cond do
      Oplog.current_xmin() > xid ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        raise "a transaction elsewhere on the database server kept running for " <>
                "#{@warm_up_wait_ms} ms, so a returning client's place would read as one from " <>
                "before the log"

      true ->
        Process.sleep(@warm_up_poll_ms)
        await_edge_past(xid, deadline)
    end
  end
end
