# TODO: refactor & test

defmodule Hologram.Compiler.IRStore do
  require Logger

  alias Hologram.Compiler.IR.ModuleDefinition
  alias Hologram.Compiler.Reflection
  alias Hologram.Utils

  @table_name :hologram_ir_store

  def create do
    :ets.new(@table_name, [:public, :named_table])
  end

  def warmup do
    Logger.debug("IR store warmup started")

    app = Application.get_all_env(:hologram)[:otp_app]
    :ok = Application.ensure_loaded(app)

    Reflection.list_modules(app)
    |> Enum.map(fn module ->
      Task.async(fn ->
        if !Reflection.is_ignored_module?(module) do
          try do
            module_def = %ModuleDefinition{} = Reflection.module_definition(module)
            put(module_def.module, module_def)
          rescue
            _ -> nil
          end
        end
      end)
    end)
    |> Utils.await_tasks()

    Logger.debug("IR store warmup finished")
  end

  def destroy do
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

  def put(key, value) do
    :ets.insert(@table_name, {key, value})
  end
end
