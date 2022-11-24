defmodule Hologram.Runtime.StaticDigestStore do
  use Hologram.Commons.MemoryStore

  alias Hologram.Compiler.Reflection
  alias Hologram.Utils

  @manifest_key :__manifest__

  @impl true
  def get(file_path) when is_binary(file_path) do
    super(String.to_atom(file_path))
  end

  @impl true
  def get(file_path) when is_atom(file_path) do
    super(file_path)
  end

  @impl true
  def populate_table(_opts) do
    digests = find_digests()

    Enum.each(digests, fn {file_path, digest} ->
      put(file_path, digest)
    end)

    put_manifest(digests)
  end

  @impl true
  def table_name, do: :hologram_static_digest_store

  defp find_digests do
    static_path = Reflection.release_static_path()
    regex = ~r/^#{Regex.escape(static_path)}(.+)\-([0-9a-f]{32})(.+)$/

    static_path
    |> Utils.list_files_recursively()
    |> Stream.map(&Regex.run(regex, &1))
    |> Stream.filter(& &1)
    |> Stream.map(&List.to_tuple/1)
    |> Stream.reject(fn {_, prefix, _, _} -> prefix == "/hologram/page" end)
    |> Stream.map(fn {_, prefix, digest, suffix} ->
      {String.to_atom(prefix <> suffix), prefix <> "-" <> digest <> suffix}
    end)
    |> Enum.to_list()
  end

  def get_manifest do
    get!(@manifest_key)
  end

  defp put_manifest(digests) do
    json =
      digests
      |> Enum.into(%{})
      |> Jason.encode!()

    content = "window.__hologramStaticDigestStore__ = #{json};"
    put(@manifest_key, content)
  end
end
