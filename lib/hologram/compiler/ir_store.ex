# TODO: refactor & test

defmodule Hologram.Compiler.IRStore do
  require Logger

  alias Hologram.Compiler.IR.ModuleDefinition
  alias Hologram.Compiler.Reflection

  @table_name :hologram_ir_store

  def create do
    :ets.new(@table_name, [:public, :named_table])
  end

  def warmup do
    Logger.debug("IR store warmup started")

    app = Application.get_all_env(:hologram)[:otp_app]
    :ok = Application.ensure_loaded(app)

    Reflection.list_modules(app)
    |> Enum.reduce([], fn module, acc ->
      if Reflection.is_ignored_module?(module) do
        acc
      else
        try do
          module_def = %ModuleDefinition{} = Reflection.module_definition(module)
          [module_def | acc]
        rescue
          _ -> acc
        end
      end
    end)
    |> Enum.each(&put(&1.module, &1))

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
