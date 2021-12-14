# TODO: refactor & test

defmodule Hologram.Compiler.ModuleDefStore do
  use GenServer

  alias Hologram.Compiler.IR.ModuleDefinition
  alias Hologram.Compiler.Reflection

  @table_name :hologram_module_def_store

  def create do
    :ets.new(@table_name, [:public, :named_table])
    start_link()
  end

  def destroy do
    Process.whereis(__MODULE__) |> Process.exit(:normal)
    :ets.delete(@table_name)
  end

  def get(key) do
    case :ets.lookup(@table_name, key) do
      [] ->
        nil

      [{^key, value}] ->
        value
    end
  end

  def get_all do
    :ets.tab2list(@table_name)
    |> Enum.into(%{})
  end

  def get_if_not_exists(module) do
    GenServer.call(__MODULE__, {:get_if_not_exists, module}, :infinity)
  end

  def init(_) do
    {:ok, %{}}
  end

  def handle_call({:get_if_not_exists, module}, _, state) do
    result =
      if get(module) do
        nil
      else
        module_def = %ModuleDefinition{} = Reflection.module_definition(module)
        put(module, module_def)
        module_def
      end

    {:reply, result, state}
  end

  def put(module, module_def) do
    :ets.insert(@table_name, {module, module_def})
  end

  def start_link do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end
end
