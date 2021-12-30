# TODO: refactor & test

defmodule Hologram.Runtime.TemplateStore do
  use GenServer

  alias Hologram.Compiler.Reflection
  alias Hologram.Utils

  @table_name :hologram_template_store

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    create_table()
    maybe_populate_table()

    {:ok, nil}
  end

  defp create_table do
    :ets.new(@table_name, [:public, :named_table])
  end

  def get(module) do
    [{^module, vdom}] = :ets.lookup(@table_name, module)
    vdom
  end

  defp maybe_populate_table do
    file_exists? =
      Reflection.release_template_store_path()
      |> File.exists?()

    if file_exists?, do: populate_table()
  end

  def populate_table do
    Reflection.release_template_store_path()
    |> File.read!()
    |> Utils.deserialize()
    |> Enum.each(fn {module, vdom} ->
      :ets.insert(@table_name, {module, vdom})
    end)
  end
end
