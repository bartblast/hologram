defmodule Hologram.Runtime.StaticDigestStore do
  use GenServer

  alias Hologram.Compiler.Reflection
  alias Hologram.Utils

  @table_name :hologram_static_digest_store

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    create_table()

    find_digests()
    |> populate_table_from_list()

    {:ok, nil}
  end

  defp create_table do
    :ets.new(@table_name, [:public, :named_table])
  end

  defp find_digests do
    regex = ~r/^(.+)\-([0-9a-f]{32})(.+)$/
    page_path_prefix = Reflection.release_priv_path() <> "/static/hologram/page"

    Reflection.release_static_path()
    |> Utils.list_files_recursively()
    |> Stream.map(&Regex.run(regex, &1))
    |> Stream.filter(&(&1))
    |> Stream.map(&List.to_tuple/1)
    |> Stream.reject(fn {_, prefix, _, _} -> prefix == page_path_prefix end)
    |> Stream.map(fn {_, prefix, digest, suffix} ->
      {String.to_atom(prefix <> suffix), digest}
    end)
    |> Enum.to_list()
  end

  defp populate_table_from_list(static_digests) do
    Enum.each(static_digests, fn {file_path, digest} ->
      :ets.insert(@table_name, {file_path, digest})
    end)
  end
end
