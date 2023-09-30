defmodule Hologram.Commons.ETS do
  def create_named_tabled(table_name) do
    :ets.new(table_name, [:named_table, :public])
    :ets.whereis(table_name)
  end
end
