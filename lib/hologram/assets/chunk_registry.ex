defmodule Hologram.Assets.ChunkRegistry do
  @moduledoc false

  use GenServer

  alias Hologram.Commons.PLT
  alias Hologram.Reflection

  @doc """
  Returns the path of the dump file used by the chunk registry registered process.
  """
  @callback dump_path() :: String.t()

  @doc """
  Returns the name of the ETS table used by the chunk registry registered process.
  """
  @callback ets_table_name() :: atom

  @doc """
  Starts chunk registry process.
  """
  @spec start_link([]) :: GenServer.on_start()
  def start_link([]) do
    GenServer.start_link(__MODULE__, nil)
  end

  @impl GenServer
  def init(nil) do
    [table_name: impl().ets_table_name()]
    |> PLT.start()
    |> populate()

    {:ok, nil}
  end

  @doc """
  Returns the implementation of the chunk registry's dump path.
  """
  @spec dump_path() :: String.t()
  def dump_path do
    Path.join([Reflection.build_dir(), Reflection.chunk_registry_plt_dump_file_name()])
  end

  @doc """
  Returns the implementation of the chunk registry's ETS table name.
  """
  @spec ets_table_name() :: atom
  def ets_table_name do
    __MODULE__
  end

  @doc """
  Returns the digests of the chunks the given page module preloads, sorted. A chunk's digest names
  its file (see `Hologram.Router.Helpers.chunk_bundle_path/1`).
  """
  @spec lookup_page(module) :: [String.t()]
  def lookup_page(page_module) do
    impl().ets_table_name()
    |> plt()
    |> PLT.get!({:page, page_module})
  end

  @doc """
  Returns the digests of the chunks the struct types the given term names need (see
  `named_modules/1`), each once, sorted: the types of the structs it holds, and the types it holds
  the module of, with which client code can build a struct of the type.
  """
  @spec lookup_term(term) :: [String.t()]
  def lookup_term(term) do
    term
    |> named_modules()
    |> Enum.flat_map(&lookup_type/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Returns the digests of the chunks the given struct type needs, sorted. A type that needs none has
  no entry, and gives an empty list.
  """
  @spec lookup_type(module) :: [String.t()]
  def lookup_type(type) do
    plt = plt(impl().ets_table_name())

    case PLT.get(plt, {:type, type}) do
      {:ok, digests} -> digests
      :error -> []
    end
  end

  @doc """
  Returns the modules the given term names, at any depth: every atom in it that has the form of a
  module's name (see `Hologram.Reflection.alias?/1`), among the keys and values of maps and of
  structs' fields, and the elements of lists (improper ones included) and tuples. The module of a
  struct the term holds is one of them, and so is a module the term holds as a value. What an
  anonymous function captures is not looked at. An atom among them that is no struct type has no
  chunk to look up (see `lookup_type/1`).
  """
  @spec named_modules(term) :: MapSet.t(module)
  def named_modules(term) do
    collect_named_modules(term, MapSet.new())
  end

  @doc """
  Reloads the chunk registry data.
  """
  @spec reload :: PLT.t()
  def reload do
    impl().ets_table_name()
    |> plt()
    |> PLT.reset()
    |> populate()
  end

  defp collect_named_modules(term, acc) when is_atom(term) do
    if Reflection.alias?(term), do: MapSet.put(acc, term), else: acc
  end

  # A struct is walked as the map it is, so its module is met as the value under :__struct__.
  defp collect_named_modules(term, acc) when is_map(term) do
    :maps.fold(
      fn key, value, entry_acc ->
        key_acc = collect_named_modules(key, entry_acc)
        collect_named_modules(value, key_acc)
      end,
      acc,
      term
    )
  end

  defp collect_named_modules([head | tail], acc) do
    head_acc = collect_named_modules(head, acc)
    collect_named_modules(tail, head_acc)
  end

  defp collect_named_modules(term, acc) when is_tuple(term) do
    term
    |> Tuple.to_list()
    |> collect_named_modules(acc)
  end

  defp collect_named_modules(_term, acc), do: acc

  defp impl do
    Application.get_env(:hologram, :chunk_registry_impl, __MODULE__)
  end

  defp plt(table_name) do
    %PLT{table_name: table_name, table_ref: :ets.whereis(table_name)}
  end

  defp populate(plt) do
    PLT.load(plt, impl().dump_path())
  end
end
