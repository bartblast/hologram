defmodule Hologram.Sync.Held do
  @moduledoc false

  # The ids of the rows a sync session's client holds, per entity type: what a batch's answers are
  # compared with to tell a row the client is given from one it is told changed, one it is told to
  # drop, and one it never had - which it is told nothing about, not even its id.
  #
  # Each type's ids are packed (see `Hologram.Sync.PackedIds`), 16 bytes an id, so a client holding
  # 10,000 rows costs its session 160 KB. A batch asks about the ids it touched, each by a search, so
  # asking costs what the batch holds rather than what the client does. Adding or taking out ids
  # copies the type's packed ids once per call, so they are added and taken out a batch at a time.

  alias Hologram.Sync.PackedIds

  @type t :: %{module => binary}

  @doc """
  Returns the given held ids with the given ids of the given entity type added.
  """
  @spec add(t, module, Enumerable.t()) :: t
  def add(held, entity_type, ids) do
    packed =
      held
      |> Map.get(entity_type, "")
      |> PackedIds.insert(ids)

    put_packed(held, entity_type, packed)
  end

  @doc """
  Returns the given held ids of the given entity type, in order.
  """
  @spec ids(t, module) :: list(String.t())
  def ids(held, entity_type) do
    held
    |> Map.get(entity_type, "")
    |> PackedIds.unpack()
  end

  @doc """
  Returns whether the given id of the given entity type is held.
  """
  @spec member?(t, module, String.t()) :: boolean
  def member?(held, entity_type, id) do
    held
    |> Map.get(entity_type, "")
    |> PackedIds.member?(id)
  end

  @doc """
  Returns held ids holding nothing.
  """
  @spec new() :: t
  def new, do: %{}

  @doc """
  Returns the given held ids with the given ids of the given entity type taken out, an id not held
  passed over.
  """
  @spec remove(t, module, Enumerable.t()) :: t
  def remove(held, entity_type, ids) do
    case Map.fetch(held, entity_type) do
      {:ok, packed} -> put_packed(held, entity_type, PackedIds.delete(packed, ids))
      :error -> held
    end
  end

  @doc """
  Splits the given packed ids of the given entity type (see `Hologram.Sync.PackedIds.pack/1`) into
  the held ones and the rest, both packed.
  """
  @spec split(t, module, binary) :: {binary, binary}
  def split(held, entity_type, packed_ids) do
    held
    |> Map.get(entity_type, "")
    |> PackedIds.split(packed_ids)
  end

  # A type the client holds none of is left out, so what is held is spelled one way only.
  defp put_packed(held, entity_type, ""), do: Map.delete(held, entity_type)

  defp put_packed(held, entity_type, packed), do: Map.put(held, entity_type, packed)
end
