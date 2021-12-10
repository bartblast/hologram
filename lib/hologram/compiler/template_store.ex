# TODO: refactor & test

defmodule Hologram.Compiler.TemplateStore do
  use GenServer

  @table_name :hologram_template_store

  def create do
    :ets.new(@table_name, [:public, :named_table])
    start_link()
  end

  def destroy do
    Process.whereis(__MODULE__) |> Process.exit(:normal)
    :ets.delete(@table_name)
  end

  def init(_) do
    {:ok, %{}}
  end

  def start_link do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end
end
