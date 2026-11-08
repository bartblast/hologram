defmodule Hologram.Assets.PathRegistry do
  @moduledoc false

  use GenServer

  alias Hologram.Commons.ETS
  alias Hologram.Reflection

  @doc """
  Returns the path of the dir that holds the bundles the compiler writes, which the registry keys
  under `hologram/`.
  """
  @callback bundles_dir() :: String.t()

  @doc """
  Returns the name of the ETS table used by the asset path registry registered process.
  """
  @callback ets_table_name() :: atom

  @doc """
  Returns the process name registered for the the asset path registry.
  """
  @callback process_name() :: atom

  @doc """
  Returns the path of the app's static dir used by the asset path registry registered process.
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
    ETS.put(ets_table_name, find_assets())

    {:ok, nil}
  end

  @doc """
  Returns the implementation of the asset path registry's bundles dir path.
  """
  @spec bundles_dir() :: String.t()
  def bundles_dir do
    Reflection.bundles_dir()
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
  Looks up the asset path (that includes the digest) of the given static path: a file in the app's
  static dir, or a bundle keyed under hologram/. If there is no matching entry for the given static
  path then :error atom is returned.
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
  Reloads the entries of Hologram's bundles, the files in the bundles dir, and leaves the other
  entries as they are.
  """
  @spec reload :: :ok
  def reload do
    list_bundle_paths()
    |> build_bundle_entries()
    |> refresh_entries(&bundle_key?/1)
  end

  @doc """
  Returns the implementation of the asset path registry's app static dir path.
  """
  @spec static_dir() :: String.t()
  def static_dir do
    Reflection.otp_app_static_dir()
  end

  @doc """
  Updates the entries the given changed files or dirs bear on, each given by its path relative to the
  app's static dir, with "" for the static dir itself: the entry of a file's key, those of the key's
  digested copies, and those of the files in a dir. A key whose files are gone loses its entry. The
  entries of Hologram's bundles, keyed under hologram/, and the other entries are left as they are.
  """
  @spec update([String.t()]) :: :ok
  def update(static_paths) do
    static_dir = impl().static_dir()
    changed_keys = MapSet.new(static_paths, &asset_key/1)
    dir_prefixes = Enum.map(static_paths, &dir_prefix/1)

    in_scope? = fn path ->
      not bundle_key?(path) and
        (MapSet.member?(changed_keys, asset_key(path)) or String.starts_with?(path, dir_prefixes))
    end

    static_dir
    |> list_app_paths()
    |> Enum.filter(in_scope?)
    |> build_entries(static_dir)
    |> refresh_entries(in_scope?)
  end

  # The key an app file is an asset of: the file's own path, or for a digested copy, the path left
  # once the digest is taken off.
  defp asset_key(relative_path) do
    case match_copy_digest(relative_path) do
      {_kind, prefix, _digest, suffix} -> prefix <> suffix
      nil -> relative_path
    end
  end

  # Maps each bundle's key, its path under hologram/ with the hash taken off, to the URL to serve it
  # from. The bundles dir holds the compiler's bundles only, so there are no copies to pick from,
  # and a file whose name carries no hash is served under its own name. A bundle takes the key of a
  # plain file that shares it, and of two bundles sharing a key, the one that sorts last is kept, so
  # that the pick is deterministic.
  defp build_bundle_entries(relative_paths) do
    {_copies, bundles, plain_files} = classify_files(relative_paths, &match_bundle_hash/1)

    bundle_entries =
      bundles
      |> Enum.sort()
      |> Enum.map(fn {key, path} -> {key, "/#{path}"} end)

    plain_entries = Enum.map(plain_files, &{&1, "/#{&1}"})

    (plain_entries ++ bundle_entries)
    |> Map.new()
    |> Map.to_list()
  end

  # Maps each asset key, the path of a file relative to the app's static dir, to the URL to serve it
  # from. A digested copy written by `mix phx.digest` stands in for its key only when copy_picker/1
  # picks it. When none is picked and nothing is at its key, each copy is a file of its own, under
  # its own name.
  defp build_entries(relative_paths, static_dir) do
    {copies, _bundles, plain_files} = classify_files(relative_paths, &match_copy_digest/1)
    pick_copy = copy_picker(static_dir)
    relative_path_set = MapSet.new(relative_paths)

    copy_entries =
      copies
      |> Enum.group_by(fn {key, _path, _digest} -> key end)
      |> Enum.flat_map(fn {key, key_copies} ->
        resolve_copies(key, key_copies, relative_path_set, pick_copy)
      end)

    plain_entries = Enum.map(plain_files, &{&1, "/#{&1}"})

    # Map.new keeps the last entry of a key: a copy takes the key of a plain file that shares it.
    (plain_entries ++ copy_entries)
    |> Map.new()
    |> Map.to_list()
  end

  defp bundle_key?(path), do: String.starts_with?(path, "hologram/")

  defp classify_file(relative_path, match_suffix) do
    case match_suffix.(relative_path) do
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

  # Splits the files into digested copies, Hologram's bundles and plain files, by the suffix the given
  # function matches, and leaves out the bundles no static path looks up, since the page digest and
  # chunk registries say which to load: a page bundle, whose name carries its page module
  # (hologram/page-<module>-<hash>.js), a chunk (hologram/chunk-<hash>.js), which all share the name
  # left once the hash is taken off, and the gzip copies and source maps of digested and hashed files.
  defp classify_files(relative_paths, match_suffix) do
    classified_files = Enum.map(relative_paths, &classify_file(&1, match_suffix))

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

  defp dir_prefix(""), do: ""

  defp dir_prefix(static_path), do: static_path <> "/"

  defp find_assets do
    static_dir = impl().static_dir()

    app_entries =
      static_dir
      |> list_app_paths()
      |> build_entries(static_dir)

    bundle_entries = build_bundle_entries(list_bundle_paths())

    app_entries ++ bundle_entries
  end

  defp impl do
    Application.get_env(:hologram, :asset_path_registry_impl, __MODULE__)
  end

  # The files of the app's static dir. A hologram dir there is where the bundles went before they
  # moved to the bundles dir, or another env's, so it's left out: only the bundles dir names this
  # env's bundles.
  defp list_app_paths(static_dir) do
    static_dir
    |> list_relative_paths()
    |> Enum.reject(&bundle_key?/1)
  end

  # The files of the bundles dir, under the hologram/ prefix the bundles' URLs start with.
  defp list_bundle_paths do
    impl().bundles_dir()
    |> list_relative_paths()
    |> Enum.map(&("hologram/" <> &1))
  end

  defp list_dir_files(dir_path) do
    case File.ls(dir_path) do
      {:ok, names} -> Enum.flat_map(names, &list_files(Path.join(dir_path, &1)))
      {:error, _reason} -> []
    end
  end

  # A file or dir that is gone by the time it is read, or a link to nothing, is left out: a tool
  # writing the static files can remove one while they are listed.
  defp list_files(path) do
    cond do
      File.regular?(path) -> [path]
      File.dir?(path) -> list_dir_files(path)
      true -> []
    end
  end

  defp list_relative_paths(static_dir) do
    static_dir
    |> list_files()
    |> Enum.map(&String.replace_prefix(&1, "#{static_dir}/", ""))
    |> Enum.sort()
  end

  # A bundle's hash suffix is the 8 chars of esbuild's content hash, which the Hologram compiler names
  # its bundles with. Matched only for the bundles: in the app's static dir a name such as
  # `arrow-DOWNLOAD.svg` would be taken for a digested `arrow.svg`.
  defp match_bundle_hash(relative_path) do
    match_digest_suffix(:esbuild, ~r"^(hologram/[^/]+)\-([A-Z2-7]{8})(\.[^/]+)$", relative_path)
  end

  # A copy's digest suffix is the 32 hex chars of an MD5, as `mix phx.digest` writes it, anywhere in
  # the app's static dir.
  defp match_copy_digest(relative_path) do
    match_digest_suffix(:md5, ~r"^(.+)\-([0-9a-f]{32})(.+)$", relative_path)
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

  # Puts the given entries in and deletes the other keys the given function holds in scope, leaving
  # the rest as they are. The new entries go in before the stale ones are deleted, so that a key kept
  # throughout is readable with its old or its new value.
  defp refresh_entries(entries, in_scope?) do
    ets_table_name = impl().ets_table_name()

    ETS.put(ets_table_name, entries)

    new_keys = MapSet.new(entries, &elem(&1, 0))

    ets_table_name
    |> ETS.keys()
    |> Enum.filter(&(is_binary(&1) and in_scope?.(&1) and not MapSet.member?(new_keys, &1)))
    |> Enum.each(&ETS.delete(ets_table_name, &1))

    :ok
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
      suffix in [".js.gz", ".js.map"]
  end

  defp unpicked_copy_entries(key, sorted_copies, relative_path_set) do
    if MapSet.member?(relative_path_set, key) do
      []
    else
      Enum.map(sorted_copies, fn {_key, path, _digest} -> {path, "/#{path}"} end)
    end
  end
end
