defmodule Hologram.Commons.PLT do
  @moduledoc """
  Provides a persistent lookup table (PLT) implemented using ETS (Erlang Term Storage) and GenServer.
  It allows to store key-value pairs in memory and perform various operations on the data.
  """

  use GenServer

  alias Hologram.Commons.PLT
  alias Hologram.Commons.SerializationUtils

  defstruct pid: nil, table_ref: nil
  @type t :: %PLT{pid: pid, table_ref: :ets.tid()}

  @doc """
  Deletes a key-value pair from the give persistent lookup table.
  """
  @spec delete(PLT.t(), atom) :: PLT.t()
  def delete(plt, key) do
    :ets.delete(plt.table_ref, key)
    plt
  end

  @doc """
  Serializes the contents of the given PLT's ETS table and writes it to a file.
  """
  @spec dump(PLT.t(), String.t()) :: :ok
  def dump(plt, path) do
    data =
      plt
      |> get_all()
      |> SerializationUtils.serialize()

    File.write!(path, data)
  end

  @doc """
  Returns the value stored in the underlying ETS table under the given key.
  If the key doesn't exist the :error :atom is returned.
  """
  @spec get(PLT.t(), atom) :: {:ok, term} | :error
  def get(%{table_ref: table_ref}, key) do
    case :ets.lookup(table_ref, key) do
      [{^key, value}] ->
        {:ok, value}

      _fallback ->
        :error
    end
  end

  @doc """
  Returns the value stored in the underlying ETS table under the given key.
  If the key doesn't exist a KeyError is raised.
  """
  @spec get!(PLT.t(), atom) :: term
  def get!(plt, key) do
    case get(plt, key) do
      {:ok, value} -> value
      _fallback -> raise KeyError, message: "key #{inspect(key)} not found in the PLT"
    end
  end

  @doc """
  Returns all items stored in the underlying ETS table.
  """
  @spec get_all(PLT.t()) :: %{atom => term}
  def get_all(%{table_ref: table_ref}) do
    table_ref
    |> :ets.tab2list()
    |> Enum.into(%{})
  end

  @doc """
  Returns the reference of the underlying ETS table.
  """
  @impl GenServer
  @spec handle_call(:get_table_ref, GenServer.from(), :ets.tid()) ::
          {:reply, :ets.tid(), :ets.tid()}
  def handle_call(:get_table_ref, _from, table_ref) do
    {:reply, table_ref, table_ref}
  end

  @doc """
  Creates the underlying ETS table.
  """
  @impl GenServer
  @spec init(nil) :: {:ok, :ets.tid()}
  def init(nil) do
    table_ref = :ets.new(__MODULE__, [:public])
    {:ok, table_ref}
  end

  @doc """
  Populates the underlying ETS table of the given PLT with items dumped to the given path.
  """
  @spec load(PLT.t(), String.t()) :: PLT.t()
  def load(plt, path) do
    items =
      path
      |> File.read!()
      |> SerializationUtils.deserialize()
      |> Map.to_list()

    put(plt, items)
  end

  @doc """
  Puts multiple items into the underlying ETS table.
  """
  @spec put(PLT.t(), keyword) :: PLT.t()
  def put(%{table_ref: table_ref} = plt, items) do
    :ets.insert(table_ref, items)
    plt
  end

  @doc """
  Puts the given item into the underlying ETS table.
  """
  @spec put(PLT.t() | :ets.tid(), atom, term) :: PLT.t() | true
  def put(plt_or_table_ref, key, value)

  def put(%PLT{table_ref: table_ref} = plt, key, value) do
    put(table_ref, key, value)
    plt
  end

  def put(table_ref, key, value) do
    :ets.insert(table_ref, {key, value})
  end

  @doc """
  Starts the underlying GenServer process.
  """
  @spec start() :: PLT.t()
  def start do
    {:ok, pid} = GenServer.start_link(PLT, nil)
    table_ref = GenServer.call(pid, :get_table_ref)

    %PLT{pid: pid, table_ref: table_ref}
  end
end
