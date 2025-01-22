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

    populate(ets_table_name)

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
    ets_table_name = impl().ets_table_name()
    ETS.reset(ets_table_name)

    populate(ets_table_name)
  end

  @doc """
  Returns the implementation of the asset path registry's static dir path.
  """
  @spec static_dir() :: String.t()
  def static_dir do
    Reflection.release_static_dir()
  end

  defp find_assets(static_dir) do
    static_files = FileUtils.list_files_recursively(static_dir)

    assets_with_digest_suffix = find_assets_with_digest_suffix(static_dir, static_files)

    already_used_registry_keys = Enum.map(assets_with_digest_suffix, &elem(&1, 0))

    assets_without_digest_suffix =
      static_dir
      |> find_assets_without_digest_suffix(static_files)
      |> Enum.reject(fn {key, _path} -> key in already_used_registry_keys end)

    assets_with_digest_suffix ++ assets_without_digest_suffix
  end

  defp find_assets_with_digest_suffix(static_dir, static_files) do
    regex = static_file_path_with_digest_suffix_regex(static_dir)

    static_files
    |> Stream.map(&Regex.run(regex, &1))
    |> Stream.filter(& &1)
    |> Stream.map(&List.to_tuple/1)
    |> stream_reject_page_bundles()
    |> stream_reject_source_maps()
    |> stream_build_asset_entries()
    |> Enum.to_list()
  end

  defp find_assets_without_digest_suffix(static_dir, static_files) do
    regex = static_file_path_with_digest_suffix_regex(static_dir)

    static_files
    |> Enum.reject(&Regex.run(regex, &1))
    |> Enum.map(fn absolute_file_path ->
      relative_file_path = String.replace_prefix(absolute_file_path, "#{static_dir}/", "")
      {relative_file_path, "/#{relative_file_path}"}
    end)
  end

  defp impl do
    Application.get_env(:hologram, :asset_path_registry_impl, __MODULE__)
  end

  defp populate(ets_table_name) do
    impl().static_dir()
    |> find_assets()
    |> Enum.each(fn {key, value} -> ETS.put(ets_table_name, key, value) end)
  end

  defp static_file_path_with_digest_suffix_regex(static_dir) do
    ~r"#{Regex.escape(static_dir)}/(.+)\-([0-9a-f]{32})(.+)$"
  end

  defp stream_build_asset_entries(file_infos) do
    Stream.map(file_infos, fn {_file_path, prefix, digest, suffix} ->
      {prefix <> suffix, "/#{prefix}-#{digest}#{suffix}"}
    end)
  end

  defp stream_reject_page_bundles(file_infos) do
    Stream.reject(file_infos, fn {_file_path, prefix, _digest, _suffix} ->
      prefix == "hologram/page"
    end)
  end

  defp stream_reject_source_maps(file_infos) do
    Stream.reject(file_infos, fn {_file_path, _prefix, _digest, suffix} ->
      suffix == ".js.map"
    end)
  end
end
