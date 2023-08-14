defmodule Hologram.Commons.PLT do
  @moduledoc """
  Provides a persistent lookup table (PLT) implemented using ETS (Erlang Term Storage) and GenServer.
  It allows to store key-value pairs in memory and perform various operations on the data.
  """

  use GenServer
  alias Hologram.Commons.PLT

  defstruct pid: nil, table_ref: nil
  @type t :: %PLT{pid: pid, table_ref: :ets.tid()}

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
  Starts the underlying GenServer process.
  """
  @spec start() :: PLT.t()
  def start do
    {:ok, pid} = GenServer.start_link(PLT, nil)
    table_ref = GenServer.call(pid, :get_table_ref)

    %PLT{pid: pid, table_ref: table_ref}
  end

  # alias Hologram.Commons.SerializationUtils

  # @doc """
  # Deletes a key-value pair from the give persistent lookup table.
  # """
  # @spec delete(PLT.t(), atom) :: PLT.t()
  # def delete(plt, key) do
  #   :ets.delete(plt.table_ref, key)
  #   plt
  # end

  # @doc """
  # Serializes the contents of the given PLT's ETS table and writes them to a file.
  # """
  # @spec dump(PLT.t()) :: :ok
  # def dump(%PLT{dump_path: dump_path} = plt) do
  #   data =
  #     plt
  #     |> get_all()
  #     |> SerializationUtils.serialize()

  #   File.write!(dump_path, data)
  # end

  # @doc """
  # Returns the value stored in the underlying ETS table under the given key.
  # If the key doesn't exist the :error :atom is returned.
  # """
  # @spec get(PLT.t(), atom) :: {:ok, term} | :error
  # def get(plt, key) do
  #   case :ets.lookup(plt.table_ref, key) do
  #     [{^key, value}] ->
  #       {:ok, value}

  #     _fallback ->
  #       :error
  #   end
  # end

  # @doc """
  # Returns the value stored in the underlying ETS table under the given key.
  # If the key doesn't exist a KeyError is raised.
  # """
  # @spec get!(PLT.t(), atom) :: term
  # def get!(plt, key) do
  #   case get(plt, key) do
  #     {:ok, value} -> value
  #     _fallback -> raise KeyError, message: "key #{inspect(key)} not found in the PLT"
  #   end
  # end

  # @doc """
  # Returns all items stored in the underlying ETS table.
  # """
  # @spec get_all(PLT.t()) :: %{atom => term}
  # def get_all(plt) do
  #   plt.table_ref
  #   |> :ets.tab2list()
  #   |> Enum.into(%{})
  # end

  # @doc """
  # Puts multiple items into the underlying ETS table.

  # """
  # @spec put(reference, keyword) :: true
  # def put(table_ref, items) do
  #   :ets.insert(table_ref, items)
  # end

  # @doc """
  # Puts the given item into the underlying ETS table.
  # """
  # @spec put(PLT.t() | atom, atom, term) :: PLT.t() | true

  # def put(%PLT{table_ref: table_ref} = plt, key, value) do
  #   put(table_ref, key, value)
  #   plt
  # end

  # def put(name, key, value) do
  #   :ets.insert(name, {key, value})
  # end

  # @doc """
  # Tells whether the underlying ETS table exists.

  # ## Examples

  #     iex> table_exists?(:my_plt)
  #     true
  # """
  # @spec table_exists?(atom) :: boolean
  # def table_exists?(name) do
  #   :ets.info(name) != :undefined
  # end

  # defp populate_table(opts) do
  #   items =
  #     opts[:dump_path]
  #     |> File.read!()
  #     |> SerializationUtils.deserialize()
  #     |> Map.to_list()

  #   put(opts[:name], items)
  # end

  # defp reload_table(opts) do
  #   truncate_table(opts[:name])

  #   if opts[:dump_path] && File.exists?(opts[:dump_path]) do
  #     populate_table_fun = opts[:populate_table_fun] || (&populate_table/1)
  #     populate_table_fun.(opts)
  #   end
  # end

  # defp truncate_table(name) do
  #   :ets.delete_all_objects(name)
  # end
end
