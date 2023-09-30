defmodule Hologram.Commons.ETS do
  @doc """
  Creates a named, public ETS table.
  """
  @spec create_named_table(atom) :: :ets.tid()
  def create_named_table(table_name) do
    :ets.new(table_name, [:named_table, :public])
    :ets.whereis(table_name)
  end

  @doc """
  Creates an unnamed, public ETS table.
  """
  @spec create_unnamed_table() :: :ets.tid()
  def create_unnamed_table do
    :ets.new(__MODULE__, [:public])
  end

  @doc """
  Puts an item into the ETS table.
  """
  @spec put(:ets.tid(), any, any) :: true
  def put(table_name_or_ref, key, value) do
    :ets.insert(table_name_or_ref, {key, value})
  end
end
