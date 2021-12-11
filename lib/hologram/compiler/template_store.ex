# TODO: refactor & test

defmodule Hologram.Compiler.TemplateStore do
  use GenServer

  alias Hologram.Compiler.Reflection
  alias Hologram.Template.Builder
  alias Hologram.Utils

  @env Application.fetch_env!(:hologram, :env)
  @table_name :hologram_template_store

  def init(_) do
    create_table()
    populate_table(@env)

    {:ok, nil}
  end

  def create_table do
    :ets.new(@table_name, [:public, :named_table])
  end

  def get(module) do
    GenServer.call(__MODULE__, {:get, module})
  end

  def handle_call({:get, module}, _, _) do
    [{^module, vdom}] = :ets.lookup(@table_name, module)
    {:reply, vdom, nil}
  end

  def populate_table(:test) do
    Reflection.list_templatables()
    |> Builder.build_all()
    |> populate_table_from_map()
  end

  def populate_table(_) do
    populate_table_from_dump()
  end

  def populate_table_from_dump do
    Reflection.template_store_dump_path()
    |> File.read!()
    |> Utils.deserialize()
    |> populate_table_from_map()
  end

  defp populate_table_from_map(templates) do
    Enum.each(templates, fn {module, vdom} ->
      :ets.insert(@table_name, {module, vdom})
    end)
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end
end
