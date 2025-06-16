defmodule Hologram.CRDT.Map do
  @moduledoc false

  # Last Writer Wins (LWW) CRDT Map implementation.

  # This CRDT map uses timestamps to resolve conflicts, with the most recent
  # write winning. Deleted entries are marked with tombstones.

  defstruct entries: %{}

  @type t :: %__MODULE__{
          entries: %{key() => entry()}
        }

  @type delta_operation :: {:put, key(), value(), timestamp()} | {:delete, key(), timestamp()}

  @type entry :: %{
          value: value(),
          timestamp: timestamp(),
          deleted: boolean()
        }

  @type key :: any()

  @type timestamp :: pos_integer()

  @type value :: any()

  @doc """
  Applies a list of delta operations to a CRDT map.
  """
  @spec apply_delta(t(), [delta_operation()]) :: t()
  def apply_delta(crdt, operations) do
    Enum.reduce(operations, crdt, fn operation, acc ->
      case operation do
        {:put, key, value, timestamp} ->
          put(acc, key, value, timestamp)

        {:delete, key, timestamp} ->
          delete(acc, key, timestamp)
      end
    end)
  end

  @doc """
  Deletes a key from the CRDT map by marking it with a tombstone.
  If no timestamp is provided, uses the current system time.

  Note: Uses microsecond precision instead of nanosecond due to the distributed
  nature of CRDTs where network latency typically exceeds nanosecond differences.
  """
  @spec delete(t(), key(), timestamp() | nil) :: t()
  def delete(crdt, key, timestamp \\ nil) do
    ts = timestamp || :os.system_time(:microsecond)
    entry = %{timestamp: ts, deleted: true}
    update_entry_if_newer(crdt, key, entry, ts)
  end

  @doc """
  Computes the delta operations needed to transform crdt_1 into crdt_2.
  Returns a list of operations that can be applied to bring crdt_1 to the state of crdt_2.
  """
  @spec delta(t(), t()) :: [delta_operation()]
  def delta(crdt_1, crdt_2) do
    keys_1 = keys_mapset(crdt_1)
    keys_2 = keys_mapset(crdt_2)
    all_keys = MapSet.union(keys_1, keys_2)

    Enum.reduce(all_keys, [], fn key, acc ->
      entry_1 = Map.get(crdt_1.entries, key)
      entry_2 = Map.get(crdt_2.entries, key)

      case {entry_1, entry_2} do
        # Key exists in crdt_2 but not in crdt_1
        {nil, entry_2} ->
          [create_delta_operation(key, entry_2) | acc]

        # Key exists in crdt_1 but not in crdt_2 - no operation needed
        {_entry_1, nil} ->
          acc

        # Key exists in both - compare timestamps
        {entry_1, entry_2} ->
          add_delta_operation_if_newer(key, entry_1, entry_2, acc)
      end
    end)
  end

  @doc """
  Checks if the CRDT map is empty (has no non-deleted entries).
  """
  @spec empty?(t()) :: boolean()
  def empty?(crdt) do
    size(crdt) == 0
  end

  @doc """
  Gets the value for a key from the CRDT map.
  Returns nil if the key doesn't exist or has been deleted.
  """
  @spec get(t(), key()) :: value() | nil
  def get(crdt, key) do
    case Map.get(crdt.entries, key) do
      nil -> nil
      %{deleted: true} -> nil
      %{value: value} -> value
    end
  end

  @doc """
  Merges two CRDT maps, with later timestamps winning conflicts.
  """
  @spec merge(t(), t()) :: t()
  def merge(crdt_1, crdt_2) do
    merged_entries =
      Map.merge(crdt_1.entries, crdt_2.entries, fn _key, entry_1, entry_2 ->
        if entry_2.timestamp > entry_1.timestamp do
          entry_2
        else
          entry_1
        end
      end)

    %__MODULE__{entries: merged_entries}
  end

  @doc """
  Creates a new empty LWW CRDT Map.
  """
  @spec new() :: t()
  def new do
    %__MODULE__{}
  end

  @doc """
  Puts a key-value pair into the CRDT map with the given timestamp.
  If no timestamp is provided, uses the current system time.

  Note: Uses microsecond precision instead of nanosecond due to the distributed
  nature of CRDTs where network latency typically exceeds nanosecond differences.
  """
  @spec put(t(), key(), value(), timestamp() | nil) :: t()
  def put(crdt, key, value, timestamp \\ nil) do
    ts = timestamp || :os.system_time(:microsecond)
    entry = %{value: value, timestamp: ts, deleted: false}
    update_entry_if_newer(crdt, key, entry, ts)
  end

  @doc """
  Returns the size (number of non-deleted entries) of the CRDT map.
  """
  @spec size(t()) :: non_neg_integer()
  def size(crdt) do
    Enum.count(crdt.entries, fn {_key, entry} -> not entry.deleted end)
  end

  @doc """
  Returns all non-deleted key-value pairs in the CRDT map.
  """
  @spec to_map(t()) :: %{key() => value()}
  def to_map(crdt) do
    crdt.entries
    |> Enum.filter(fn {_key, entry} -> not entry.deleted end)
    |> Enum.into(%{}, fn {key, entry} -> {key, entry.value} end)
  end

  # Helper function to add delta operation if entry_2 has newer timestamp
  defp add_delta_operation_if_newer(key, entry_1, entry_2, acc) do
    if entry_2.timestamp > entry_1.timestamp do
      [create_delta_operation(key, entry_2) | acc]
    else
      acc
    end
  end

  # Helper function to create delta operations based on entry state
  defp create_delta_operation(key, entry) do
    if entry.deleted do
      {:delete, key, entry.timestamp}
    else
      {:put, key, entry.value, entry.timestamp}
    end
  end

  # Helper function to extract keys from a CRDT as a MapSet
  defp keys_mapset(crdt) do
    crdt.entries
    |> Map.keys()
    |> MapSet.new()
  end

  # Helper function to update an entry if the new timestamp is newer
  defp update_entry_if_newer(crdt, key, new_entry, new_timestamp) do
    case Map.get(crdt.entries, key) do
      nil ->
        # No existing entry, add the new one
        %{crdt | entries: Map.put(crdt.entries, key, new_entry)}

      existing_entry ->
        # Update only if timestamp is newer
        if new_timestamp > existing_entry.timestamp do
          %{crdt | entries: Map.put(crdt.entries, key, new_entry)}
        else
          crdt
        end
    end
  end
end
