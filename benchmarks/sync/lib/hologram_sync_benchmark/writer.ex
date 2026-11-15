defmodule HologramSyncBenchmark.Writer do
  @moduledoc false

  # A timed write, run on the server node the way an action's write runs there: read the row,
  # change it, write it back through the Writer, which logs the effect and notifies the nodes in
  # the same transaction.

  use Hologram.DB

  alias Hologram.DB

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
end
