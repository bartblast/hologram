# TODO: test

defmodule Hologram.Runtime.PageDigestStore do
  use GenServer

  alias Hologram.Compiler.Reflection
  alias Hologram.Utils

  @env Application.fetch_env!(:hologram, :env)
  @table_name :hologram_page_digest_store

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    create_table()
    populate_table(@env)

    {:ok, nil}
  end

  defp create_table do
    :ets.new(@table_name, [:public, :named_table])
  end

  def get(module) do
    [{^module, digest}] = :ets.lookup(@table_name, module)
    digest
  end

  defp populate_table(:test), do: nil

  defp populate_table(_) do
    populate_table_from_file()
  end

  defp populate_table_from_file do
    Reflection.release_page_digest_store_path()
    |> File.read!()
    |> Utils.deserialize()
    |> populate_table_from_list()
  end

  defp populate_table_from_list(page_digests) do
    Enum.each(page_digests, fn {module, digest} ->
      :ets.insert(@table_name, {module, digest})
    end)
  end
end
