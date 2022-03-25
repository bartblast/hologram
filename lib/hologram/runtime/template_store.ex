# TODO: create Hologram.Commons.Store behaviour and use it in ModuleDefStore, PageDigestStore, StaticDigestStore, TemplateStore
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

  def clean_table do
    :ets.delete_all_objects(@table_name)
  end

  def create do
    :ets.new(@table_name, [:public, :named_table])
    start_link(nil)
  end

  defp create_table do
    :ets.new(@table_name, [:public, :named_table])
  end

  def get(module) do
    [{^module, vdom}] = :ets.lookup(@table_name, module)
    vdom
  end

  def get_all do
    :ets.tab2list(@table_name)
    |> Enum.into(%{})
  end

  def is_running? do
    Process.whereis(__MODULE__) != nil
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

  def put(module, template) do
    :ets.insert(@table_name, {module, template})
  end

  def reset do
    if is_running?() && table_created?() do
      clean_table()
    else
      create()
    end
  end

  defp table_created? do
    :ets.info(@table_name) != :undefined
  end
end
