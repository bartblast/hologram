defmodule Hologram.Commons.PLT do
  @moduledoc false

  # Provides a persistent lookup table (PLT) implemented using ETS (Erlang Term Storage) and GenServer.
  # It allows to store key-value pairs in memory and perform various operations on the data.
  # The data in memory can be dumped to a file and loaded from a file.

  use GenServer

  alias Hologram.Commons.ETS
  alias Hologram.Commons.PLT
  alias Hologram.Commons.SerializationUtils
  alias Hologram.Commons.Types, as: T

  defstruct pid: nil, table_ref: nil, table_name: nil
  @type t :: %PLT{pid: pid | nil, table_ref: ETS.tid() | nil, table_name: atom | nil}

  @doc """
  Returns a clone of the PLT.
  """
  @spec clone(PLT.t()) :: PLT.t()
  def clone(plt) do
    items =
      plt
      |> get_all()
      |> Map.to_list()

    put(start(), items)
  end

  @doc """
  Deletes a key-value pair from the PLT.
  """
  @spec delete(PLT.t(), any) :: PLT.t()
  def delete(%{table_ref: table_ref} = plt, key) do
    ETS.delete(table_ref, key)
    plt
  end

  @doc """
  Serializes the contents of the PLT and writes it to a file.

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/commons/plt/dump_2/README.md
  """
  @spec dump(PLT.t(), String.t()) :: PLT.t()
  def dump(plt, path) do
    data =
      plt
      |> get_all()
      |> SerializationUtils.serialize()

    path
    |> Path.dirname()
    |> File.mkdir_p!()

    File.write!(path, data)

    plt
  end

  @doc """
  Returns the value stored in the PLT under the given key.
  If the key doesn't exist the :error :atom is returned.
  """
  @spec get(PLT.t(), any) :: {:ok, term} | :error
  def get(%{table_ref: table_ref, table_name: table_name}, key) do
    ETS.get(table_ref || table_name, key)
  end

  @doc """
  Returns the value stored in the PLT under the given key.
  If the key doesn't exist a KeyError is raised.
  """
  @spec get!(PLT.t(), any) :: term
  def get!(plt, key) do
    case get(plt, key) do
      {:ok, value} -> value
      _fallback -> raise KeyError, message: "key #{inspect(key)} not found in the PLT"
    end
  end

  @doc """
  Returns all items stored in the PLT.
  """
  @spec get_all(PLT.t()) :: map
  def get_all(%{table_ref: table_ref}) do
    ETS.get_all(table_ref)
  end

  @doc """
  Returns the reference of the underlying ETS table.
  """
  @impl GenServer
  @spec handle_call(:get_table_ref, GenServer.from(), ETS.tid()) ::
          {:reply, ETS.tid(), ETS.tid()}
  def handle_call(:get_table_ref, _from, table_ref) do
    {:reply, table_ref, table_ref}
  end

  @doc """
  Creates the underlying ETS table.
  """
  @impl GenServer
  @spec init(atom | nil) :: {:ok, ETS.tid()}
  def init(table_name)

  def init(nil) do
    {:ok, ETS.create_unnamed_table()}
  end

  def init(table_name) do
    {:ok, ETS.create_named_table(table_name)}
  end

  @doc """
  Populates the PLT with items dumped to the given file.
  """
  @spec load(PLT.t(), String.t()) :: PLT.t()
  def load(plt, dump_path) do
    items =
      dump_path
      |> File.read!()
      |> SerializationUtils.deserialize(true)
      |> Map.to_list()

    put(plt, items)
  end

  @doc """
  Populates the PLT with items dumped to the given file if the file exists.
  """
  @spec maybe_load(PLT.t(), String.t()) :: PLT.t()
  def maybe_load(plt, dump_path) do
    if File.exists?(dump_path) do
      load(plt, dump_path)
    else
      plt
    end
  end

  @doc """
  Puts multiple items into the PLT.
  """
  @spec put(PLT.t(), list({any, any})) :: PLT.t()
  def put(%{table_ref: table_ref} = plt, items) do
    ETS.put(table_ref, items)
    plt
  end

  @doc """
  Puts the given item into the PLT.
  """
  @spec put(PLT.t(), any, any) :: PLT.t()
  def put(%PLT{table_ref: table_ref} = plt, key, value) do
    ETS.put(table_ref, key, value)
    plt
  end

  @doc """
  Removes all items from the PLT.
  """
  @spec reset(PLT.t()) :: PLT.t()
  def reset(%PLT{table_ref: table_ref} = plt) do
    ETS.reset(table_ref)
    plt
  end

  @doc """
  Returns the number of items in the PLT.
  """
  @spec size(PLT.t()) :: integer
  def size(plt) do
    plt
    |> get_all()
    |> Enum.count()
  end

  @doc """
  Starts the underlying GenServer process.
  """
  @spec start(T.opts()) :: PLT.t()
  def start(opts \\ []) do
    genserver_opts = Keyword.delete(opts, :table_name)

    {:ok, pid} = GenServer.start_link(PLT, opts[:table_name], genserver_opts)
    table_ref = GenServer.call(pid, :get_table_ref)

    plt = %PLT{pid: pid, table_ref: table_ref, table_name: opts[:table_name]}

    if opts[:items], do: PLT.put(plt, opts[:items])

    plt
  end

  @doc """
  Stops the underlying GenServer process.
  """
  @spec stop(PLT.t()) :: :ok
  def stop(%PLT{pid: pid}) do
    GenServer.stop(pid)
  end
end
