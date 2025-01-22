defmodule Hologram.Commons.ETS do
  @moduledoc false

  # This helps to avoid Dialyzer warnings related to :ets.tid() type opaqueness.
  @type tid :: :ets.tid() | atom

  @doc """
  Creates a named, public ETS table.
  """
  @spec create_named_table(atom) :: tid
  def create_named_table(table_name) do
    :ets.new(table_name, [:named_table, :public])
    :ets.whereis(table_name)
  end

  @doc """
  Creates an unnamed, public ETS table.
  """
  @spec create_unnamed_table() :: tid
  def create_unnamed_table do
    :ets.new(__MODULE__, [:public])
  end

  @doc """
  Deletes the ETS table if it exists.
  """
  @spec delete(tid) :: boolean
  def delete(table_name_or_ref) do
    delete!(table_name_or_ref)
  rescue
    ArgumentError -> false
  end

  @doc """
  Deletes the ETS table if it exists or raises ArgumentError otherwise.
  """
  @spec delete!(tid) :: true
  def delete!(table_name_or_ref) do
    :ets.delete(table_name_or_ref)
  end

  @doc """
  Deletes a key-value pair from the ETS table.
  """
  @spec delete(tid, any) :: true
  def delete(table_name_or_ref, key) do
    :ets.delete(table_name_or_ref, key)
  end

  @doc """
  Returns the value stored in the ETS table under the given key.
  If the key doesn't exist the :error :atom is returned.
  """
  @spec get(tid, any) :: {:ok, term} | :error
  def get(table_name_or_ref, key) do
    case :ets.lookup(table_name_or_ref, key) do
      [{^key, value}] ->
        {:ok, value}

      _fallback ->
        :error
    end
  end

  @doc """
  Returns the value stored in the ETS table under the given key.
  If the key doesn't exist a KeyError is raised.
  """
  @spec get!(tid, any) :: term
  def get!(table_name_or_ref, key) do
    case get(table_name_or_ref, key) do
      {:ok, value} -> value
      _fallback -> raise KeyError, message: "key #{inspect(key)} not found in the ETS table"
    end
  end

  @doc """
  Returns all items stored in the ETS table.
  """
  @spec get_all(tid) :: map
  def get_all(table_name_or_ref) do
    table_name_or_ref
    |> :ets.tab2list()
    |> Enum.into(%{})
  end

  @doc """
  Puts multiple items into the ETS table.
  """
  @spec put(tid, list({any, any})) :: true
  def put(table_name_or_ref, items) do
    :ets.insert(table_name_or_ref, items)
  end

  @doc """
  Puts an item into the ETS table.
  """
  @spec put(tid, any, any) :: true
  def put(table_name_or_ref, key, value) do
    :ets.insert(table_name_or_ref, {key, value})
  end

  @doc """
  Removes all items from the ETS table.
  """
  @spec reset(tid) :: true
  def reset(table_name_or_ref) do
    :ets.delete_all_objects(table_name_or_ref)
  end

  @doc """
  Determines whether the given ETS table exists.
  """
  @spec table_exists?(tid()) :: boolean
  def table_exists?(table_ref_or_name)
      when is_atom(table_ref_or_name) or is_reference(table_ref_or_name) do
    table_ref_or_name
    |> :ets.info()
    |> is_list()
  rescue
    ArgumentError -> false
  end
end
