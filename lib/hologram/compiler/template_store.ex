# TODO: refactor & test

defmodule Hologram.Compiler.TemplateStore do
  use GenServer

  alias Hologram.Compiler.Reflection
  alias Hologram.Utils

  @table_name :hologram_template_store

  def init(_) do
    maybe_create_table()
    maybe_populate_table_from_dump()

    {:ok, nil}
  end

  def get(module) do
    GenServer.call(__MODULE__, {:get, module})
  end

  def handle_call({:get, module}, _, _) do
    [{^module, vdom}] = :ets.lookup(@table_name, module)
    {:reply, vdom, nil}
  end

  def maybe_create_table do
    if :ets.whereis(@table_name) == :undefined do
      :ets.new(@table_name, [:public, :named_table])
    end
  end

  def maybe_populate_table_from_dump do
    path = Reflection.template_store_dump_path()

    if File.exists?(path) do
      path
      |> File.read!()
      |> Utils.deserialize()
      |> populate()
    end
  end

  def populate(templates) do
    Enum.each(templates, fn {module, vdom} ->
      :ets.insert(@table_name, {module, vdom})
    end)
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end
end
