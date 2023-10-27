defmodule Hologram.Runtime.AssetPathRegistry do
  use GenServer

  alias Hologram.Commons.ETS
  alias Hologram.Commons.FileUtils
  alias Hologram.Commons.Reflection

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
  @callback static_dir_path() :: String.t()

  @doc """
  Starts asset path registry process.
  """
  @spec start_link([]) :: GenServer.on_start()
  def start_link([]) do
    GenServer.start_link(__MODULE__, nil, name: impl().process_name())
  end

  @impl GenServer
  def init(nil) do
    impl().ets_table_name()
    |> tap(&ETS.create_named_table(&1))
    |> then(fn ets_table_name ->
      impl().static_dir_path()
      |> find_assets()
      |> Enum.each(fn {key, value} -> ETS.put(ets_table_name, key, value) end)
    end)

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
  Returns the implementation of the asset path registry's static dir path.
  """
  @spec static_dir_path() :: String.t()
  def static_dir_path do
    Reflection.release_static_path()
  end

  defp find_assets(static_dir_path) do
    static_dir_path
    |> Regex.escape()
    |> then(&~r"#{&1}/(.+)\-([0-9a-f]{32})(.+)$")
    |> then(fn regex ->
      static_dir_path
      |> FileUtils.list_files_recursively()
      |> Stream.map(&Regex.run(regex, &1))
      |> Stream.filter(& &1)
      |> Stream.map(&List.to_tuple/1)
      |> stream_reject_page_bundles()
      |> stream_build_asset_entries()
      |> Enum.to_list()
    end)
  end

  defp impl do
    Application.get_env(:hologram, :asset_path_registry_impl, __MODULE__)
  end

  defp stream_build_asset_entries(file_infos) do
    Stream.map(file_infos, fn {_file_path, prefix, digest, suffix} ->
      {prefix <> suffix, "/#{prefix}-#{digest}#{suffix}"}
    end)
  end

  defp stream_reject_page_bundles(file_infos) do
    Stream.reject(file_infos, &(elem(&1, 1) == "hologram/page"))
  end
end
