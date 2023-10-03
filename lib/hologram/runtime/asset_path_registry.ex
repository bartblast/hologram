defmodule Hologram.Runtime.AssetPathRegistry do
  use GenServer

  alias Hologram.Commons.ETS
  alias Hologram.Commons.FileUtils
  alias Hologram.Commons.Reflection

  @default_ets_table_name __MODULE__

  @doc """
  Starts AssetDigestLookup process.
  """
  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts) do
    opts = Keyword.put_new(opts, :process_name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: opts[:process_name])
  end

  @impl GenServer
  def init(opts) do
    opts =
      opts
      |> Keyword.put_new(:ets_table_name, @default_ets_table_name)
      |> Keyword.put_new(:static_path, Reflection.release_static_path())

    ETS.create_named_table(opts[:ets_table_name])

    opts[:static_path]
    |> find_assets()
    |> Enum.each(fn {key, value} -> ETS.put(opts[:ets_table_name], key, value) end)

    {:ok, opts[:ets_table_name]}
  end

  @doc """
  Returns the asset path mapping.
  """
  @impl GenServer
  @spec handle_call(:get_mapping, GenServer.from(), :ets.tid()) ::
          {:reply, %{String.t() => String.t()}, :ets.tid()}
  def handle_call(:get_mapping, _from, ets_table_name) do
    {:reply, ETS.get_all(ets_table_name), ets_table_name}
  end

  @doc """
  Looks up the asset path (that includes the digest) of the given static file located in static dir.
  If there is no matching entry for the given static file then :error atom is returned.
  """
  @spec lookup(String.t(), ETS.tid()) :: {:ok, String.t()} | :error
  def lookup(static_path, ets_table_name \\ @default_ets_table_name) do
    ETS.get(ets_table_name, static_path)
  end

  defp find_assets(static_path) do
    regex = ~r/^#{Regex.escape(static_path)}(.+)\-([0-9a-f]{32})(.+)$/

    static_path
    |> FileUtils.list_files_recursively()
    |> Stream.map(&Regex.run(regex, &1))
    |> Stream.filter(& &1)
    |> Stream.map(&List.to_tuple/1)
    |> stream_reject_page_bundles()
    |> stream_build_asset_entries()
    |> Enum.to_list()
  end

  defp stream_build_asset_entries(file_infos) do
    Stream.map(file_infos, fn {_file_path, prefix, digest, suffix} ->
      {prefix <> suffix, prefix <> "-" <> digest <> suffix}
    end)
  end

  defp stream_reject_page_bundles(file_infos) do
    Stream.reject(file_infos, fn {_file_path, prefix, _digest, _suffix} ->
      prefix == "/hologram/page"
    end)
  end
end
