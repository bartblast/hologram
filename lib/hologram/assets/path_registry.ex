defmodule Hologram.Assets.PathRegistry do
  @moduledoc false

  use GenServer

  alias Hologram.Commons.ETS
  alias Hologram.Commons.FileUtils
  alias Hologram.Reflection

  @doc """
  Returns the name of the ETS table used by the asset path registry registered process.
  """
  @callback ets_table_name() :: atom

  @doc """
  Returns the process name registered for the the asset path registry.
  """
  @callback process_name() :: atom

  @doc """
  Returns the path of the static dir used by the asset path registry registered process.
  """
  @callback static_dir() :: String.t()

  @doc """
  Starts asset path registry process.
  """
  @spec start_link([]) :: GenServer.on_start()
  def start_link([]) do
    GenServer.start_link(__MODULE__, nil, name: impl().process_name())
  end

  @impl GenServer
  def init(nil) do
    ets_table_name = impl().ets_table_name()
    ETS.create_named_table(ets_table_name)
    ETS.put(ets_table_name, find_assets(impl().static_dir()))

    {:ok, nil}
  end

  @doc """
  Returns the asset path mapping.
  """
  @impl GenServer
  @spec handle_call(:get_mapping, GenServer.from(), nil) ::
          {:reply, %{String.t() => String.t()}, nil}
  def handle_call(:get_mapping, _from, nil) do
    {:reply, ETS.get_all(impl().ets_table_name()), nil}
  end

  @doc """
  Returns the implementation of the asset path registry's ETS table name.
  """
  @spec ets_table_name() :: atom
  def ets_table_name do
    __MODULE__
  end

  @doc """
  Returns the asset path mapping.
  """
  @spec get_mapping() :: %{String.t() => String.t()}
  def get_mapping do
    GenServer.call(impl().process_name(), :get_mapping)
  end

  @doc """
  Looks up the asset path (that includes the digest) of the given static file located in static dir.
  If there is no matching entry for the given static file then :error atom is returned.
  """
  @spec lookup(String.t()) :: {:ok, String.t()} | :error
  def lookup(static_path) do
    ETS.get(impl().ets_table_name(), static_path)
  end

  @doc """
  Returns the implementation of the asset path registry's process name.
  """
  @spec process_name() :: atom
  def process_name do
    __MODULE__
  end

  @doc """
  Registers the given asset path under the given static path key in the registry.
  """
  @spec register(String.t(), String.t()) :: true
  def register(static_path, asset_path) do
    ETS.put(impl().ets_table_name(), static_path, asset_path)
  end

  @doc """
  Reloads the path registry data.
  """
  @spec reload :: :ok
  def reload do
    ETS.replace_all(impl().ets_table_name(), find_assets(impl().static_dir()))
    :ok
  end

  @doc """
  Returns the implementation of the asset path registry's static dir path.
  """
  @spec static_dir() :: String.t()
  def static_dir do
    Reflection.otp_app_static_dir()
  end

  # Maps each asset key, the path of a file relative to the static dir, to the URL to serve it
  # from. A digested copy written by `mix phx.digest` stands in for its key only when copy_picker/1
  # picks it. When none is picked and nothing is at its key, each copy is a file of its own, under
  # its own name.
  defp build_entries(relative_paths, static_dir) do
    {copies, bundles, plain_files} = classify_files(relative_paths)
    pick_copy = copy_picker(static_dir)
    relative_path_set = MapSet.new(relative_paths)

    copy_entries =
      copies
      |> Enum.group_by(fn {key, _path, _digest} -> key end)
      |> Enum.flat_map(fn {key, key_copies} ->
        resolve_copies(key, key_copies, relative_path_set, pick_copy)
      end)

    bundle_entries = Enum.map(bundles, fn {key, path} -> {key, "/#{path}"} end)
    plain_entries = Enum.map(plain_files, &{&1, "/#{&1}"})

    # Map.new keeps the last entry of a key: a copy or a bundle takes the key of a plain file that
    # shares it, and of two bundles sharing a key, the one that sorts last, so that the pick is
    # deterministic.
    (plain_entries ++ bundle_entries ++ copy_entries)
    |> Map.new()
    |> Map.to_list()
  end

  defp classify_file(relative_path) do
    case match_digest_suffix(relative_path) do
      {kind, prefix, digest, suffix} ->
        cond do
          unlooked_up_bundle?(prefix, suffix) -> :unlooked_up_bundle
          kind == :md5 -> {:copy, prefix <> suffix, relative_path, digest}
          true -> {:bundle, prefix <> suffix, relative_path}
        end

      nil ->
        {:plain, relative_path}
    end
  end

  # Splits the files into digested copies, Hologram's bundles and plain files, and leaves out the
  # bundles no static path looks up, since the page digest and chunk registries say which to load:
  # a page bundle, whose name carries its page module (hologram/page-<module>-<hash>.js), a chunk
  # (hologram/chunk-<hash>.js), which all share the name left once the hash is taken off, and the
  # source maps of digested and hashed files.
  defp classify_files(relative_paths) do
    classified_files = Enum.map(relative_paths, &classify_file/1)

    copies = for {:copy, key, path, digest} <- classified_files, do: {key, path, digest}
    bundles = for {:bundle, key, path} <- classified_files, do: {key, path}
    plain_files = for {:plain, path} <- classified_files, do: path

    {copies, bundles, plain_files}
  end

  # In dev and test the static files change after `mix phx.digest` ran, so a copy counts only while
  # its digest is the MD5 of the file at its key, which is how phx.digest names it. Elsewhere the
  # static files are built once, and the cache manifest phx.digest writes along names the latest
  # copy of each key, which also settles between the copies of an earlier run, with no file read.
  defp copy_picker(static_dir) do
    if Hologram.env() in [:dev, :test] do
      &pick_copy_by_content(static_dir, &1, &2)
    else
      latest_copies = read_latest_copies(static_dir)
      &pick_copy_by_manifest(latest_copies, &1, &2)
    end
  end

  defp find_assets(static_dir) do
    static_dir
    |> FileUtils.list_files_recursively()
    |> Enum.map(&String.replace_prefix(&1, "#{static_dir}/", ""))
    |> build_entries(static_dir)
  end

  defp impl do
    Application.get_env(:hologram, :asset_path_registry_impl, __MODULE__)
  end

  # A digest suffix is the 32 hex chars of an MD5, as `mix phx.digest` writes it, anywhere in the
  # static dir, or the 8 chars of esbuild's content hash, which the Hologram compiler names its
  # bundles with, only in the hologram dir. Anywhere else a name such as `arrow-DOWNLOAD.svg` would
  # be taken for a digested `arrow.svg`. The MD5 form is tried first, so a compiler bundle that
  # `mix phx.digest` digested again is read as a copy of the bundle.
  defp match_digest_suffix(relative_path) do
    with nil <- match_digest_suffix(:md5, ~r"^(.+)\-([0-9a-f]{32})(.+)$", relative_path) do
      match_digest_suffix(:esbuild, ~r"^(hologram/[^/]+)\-([A-Z2-7]{8})(\.[^/]+)$", relative_path)
    end
  end

  defp match_digest_suffix(kind, regex, relative_path) do
    case Regex.run(regex, relative_path) do
      [_relative_path, prefix, digest, suffix] -> {kind, prefix, digest, suffix}
      nil -> nil
    end
  end

  defp md5_digest(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        content
        |> :erlang.md5()
        |> Base.encode16(case: :lower)

      {:error, _reason} ->
        nil
    end
  end

  defp pick_copy_by_content(static_dir, key, key_copies) do
    file_digest =
      static_dir
      |> Path.join(key)
      |> md5_digest()

    Enum.find(key_copies, fn {_key, _path, digest} -> digest == file_digest end)
  end

  defp pick_copy_by_manifest(latest_copies, key, key_copies) do
    Enum.find(key_copies, fn {_key, path, _digest} -> path == latest_copies[key] end)
  end

  # The "latest" map of the cache manifest `mix phx.digest` writes, from each key to its newest
  # copy. A manifest that is missing or unreadable names no copy, so the plain files are served:
  # Phoenix logs such a manifest at its endpoint's start and serves the plain files too.
  defp read_latest_copies(static_dir) do
    manifest_path = Path.join(static_dir, "cache_manifest.json")

    with {:ok, json} <- File.read(manifest_path),
         {:ok, %{"latest" => latest_copies}} when is_map(latest_copies) <- JSON.decode(json) do
      latest_copies
    else
      _no_latest_copies -> %{}
    end
  end

  # The copy copy_picker/1 picks stands in for the key. With none, the file at the key is served, and
  # when nothing is at the key, each copy is served under its own name.
  defp resolve_copies(key, key_copies, relative_path_set, pick_copy) do
    sorted_copies = Enum.sort(key_copies)

    case pick_copy.(key, sorted_copies) do
      {_key, path, _digest} ->
        [{key, "/#{path}"}]

      nil ->
        unpicked_copy_entries(key, sorted_copies, relative_path_set)
    end
  end

  defp unlooked_up_bundle?(prefix, suffix) do
    prefix == "hologram/chunk" or String.starts_with?(prefix, "hologram/page-") or
      suffix == ".js.map"
  end

  defp unpicked_copy_entries(key, sorted_copies, relative_path_set) do
    if MapSet.member?(relative_path_set, key) do
      []
    else
      Enum.map(sorted_copies, fn {_key, path, _digest} -> {path, "/#{path}"} end)
    end
  end
end
