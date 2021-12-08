# TODO: test

defmodule Hologram.Compiler.IRStore do
  @table_name :hologram_ir_store

  def init do
    :ets.new(@table_name, [:public, :named_table])
  end

  def get(key) do
    case :ets.lookup(@table_name, key) do
      [] ->
        nil
      [{^key, value}] ->
        value
    end
  end

  def put(key, value) do
    :ets.insert(@table_name, {key, value})
  end
end
