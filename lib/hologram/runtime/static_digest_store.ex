# DEFER: test

defmodule Hologram.Runtime.StaticDigestStore do
  use GenServer

  alias Hologram.Compiler.Reflection
  alias Hologram.Utils

  @table_name :hologram_static_digest_store

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    digests = find_digests()

    create_table()
    populate_table(digests)
    create_manifest_file(digests)

    {:ok, nil}
  end

  defp create_manifest_file(digests) do
    json =
      digests
      |> Enum.into(%{})
      |> Jason.encode!()

    content = "window.__hologramStaticManifest__ = #{json}"

    Reflection.release_static_path() <> "/hologram/manifest.js"
    |> File.write!(content)
  end

  defp create_table do
    :ets.new(@table_name, [:public, :named_table])
  end

  defp find_digests do
    static_path = Reflection.release_priv_path() <> "/static"
    regex = ~r/^#{Regex.escape(static_path)}(.+)\-([0-9a-f]{32})(.+)$/

    Reflection.release_static_path()
    |> Utils.list_files_recursively()
    |> Stream.map(&Regex.run(regex, &1))
    |> Stream.filter(&(&1))
    |> Stream.map(&List.to_tuple/1)
    |> Stream.reject(fn {_, prefix, _, _} -> prefix == "/hologram/page" end)
    |> Stream.map(fn {_, prefix, digest, suffix} ->
      {String.to_atom(prefix <> suffix), prefix <> "-" <> digest <> suffix}
    end)
    |> Enum.to_list()
  end

  def get(file_path) do
    key = String.to_atom(file_path)

    case :ets.lookup(@table_name, key) do
      [{^key, digest}] ->
        digest

      _ ->
        file_path
    end
  end

  defp populate_table(static_digests) do
    Enum.each(static_digests, fn {file_path, digest} ->
      :ets.insert(@table_name, {file_path, digest})
    end)
  end
end
