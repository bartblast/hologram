defmodule Hologram.Commons.PLT do
  @moduledoc """
  Provides a persistent lookup table (PLT) implemented using ETS (Erlang Term Storage) and GenServer.
  It allows to store key-value pairs in memory and perform various operations on the data.
  The data in memory can be dumped to a file and loaded from a file.
  """

  use GenServer

  alias Hologram.Commons.ETS
  alias Hologram.Commons.PLT
  alias Hologram.Commons.SerializationUtils

  defstruct pid: nil, table_ref: nil, table_name: nil
  @type t :: %PLT{pid: pid | nil, table_ref: ETS.tid() | nil, table_name: atom | nil}

  @doc """
  Deletes a key-value pair from the underlying ETS table.
  """
  @spec delete(PLT.t(), any) :: PLT.t()
  def delete(plt, key) do
    tap(plt, &ETS.delete(&1.table_ref, key))
  end

  @doc """
  Serializes the contents of the given PLT's ETS table and writes it to a file.
  """
  @spec dump(PLT.t(), String.t()) :: PLT.t()
  def dump(plt, path) do
    data =
      plt
      |> get_all()
      |> SerializationUtils.serialize()

    File.mkdir_p!(Path.dirname(path))
    File.write!(path, data)

    plt
  end

  @doc """
  Returns the value stored in the underlying ETS table under the given key.
  If the key doesn't exist the :error :atom is returned.
  """
  @spec get(PLT.t(), any) :: {:ok, term} | :error
  def get(%{table_ref: table_ref, table_name: table_name}, key) do
    ETS.get(table_ref || table_name, key)
  end

  @doc """
  Returns the value stored in the underlying ETS table under the given key.
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
  Returns all items stored in the underlying ETS table.
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
  Populates the underlying ETS table of the given PLT with items dumped to the given file.
  """
  @spec load(PLT.t(), String.t()) :: PLT.t()
  def load(plt, dump_path) do
    dump_path
    |> File.read!()
    |> SerializationUtils.deserialize(true)
    |> Map.to_list()
    |> then(&put(plt, &1))
  end

  @doc """
  Populates the underlying ETS table of the given PLT with items dumped to the given file if the file exists.
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
  Puts multiple items into the underlying ETS table.
  """
  @spec put(PLT.t(), list({any, any})) :: PLT.t()
  def put(plt, items) do
    tap(plt, &ETS.put(&1.table_ref, items))
  end

  @doc """
  Puts the given item into the underlying ETS table.
  """
  @spec put(PLT.t(), any, any) :: PLT.t()
  def put(plt, key, value) do
    tap(plt, &ETS.put(&1.table_ref, key, value))
  end

  @doc """
  Starts the underlying GenServer process.
  """
  @spec start(keyword) :: PLT.t()
  def start(opts \\ []) do
    opts
    |> Keyword.delete(:table_name)
    |> then(&GenServer.start_link(PLT, opts[:table_name], &1))
    |> then(fn {:ok, pid} ->
      pid
      |> GenServer.call(:get_table_ref)
      |> then(&%PLT{pid: pid, table_ref: &1, table_name: opts[:table_name]})
    end)
  end
end
