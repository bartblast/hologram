defmodule Hologram.Compiler.ModuleDefStore do
  use Hologram.Commons.MemoryStore

  alias Hologram.Compiler.IR.ModuleDefinition
  alias Hologram.Compiler.Reflection

  @impl true
  def table_name, do: :hologram_module_def_store

  def get_if_not_exists(module) do
    GenServer.call(__MODULE__, {:get_if_not_exists, module}, :infinity)
  end

  def handle_call({:get_if_not_exists, module}, _, state) do
    result =
      case get(module) do
        {:ok, _} ->
          nil
        :error ->
          module_def = %ModuleDefinition{} = Reflection.module_definition(module)
          put(module, module_def)
          module_def
      end

    {:reply, result, state}
  end
end
