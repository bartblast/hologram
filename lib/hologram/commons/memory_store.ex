defmodule Hologram.Commons.MemoryStore do
  defmacro __using__(_opts) do
    quote do
      use GenServer

      alias Hologram.Commons.MemoryStore
      alias Hologram.Commons.SerializationUtils

      @behaviour MemoryStore

      @doc """
      Starts the underlying GenServer process.

      ## Examples

          iex> MyMemoryStore.run()
          {:ok, #PID<0.273.0>}
      """
      @spec run() :: {:ok, pid} | :ignore | {:error, {:already_started, pid} | term}
      def run do
        GenServer.start_link(__MODULE__, nil, name: __MODULE__)
      end

      @doc """
      Creates the underlying ETS table if it doesn't exist yet, truncates it and populates it.

      ## Examples

          iex> MyMemoryStore.init(nil)
          {:ok, nil}
      """
      @impl GenServer
      @spec init(nil) :: {:ok, nil}
      def init(nil) do
        maybe_create_table()
        reload_table()
        {:ok, nil}
      end

      @doc """
      Returns the value stored in the underlying ETS table under the given key.

      ## Examples

          iex> MyMemoryStore.get(:my_key)
          :my_value
      """
      @spec get(atom | binary) :: {:ok, term} | :error
      def get(key) do
        case :ets.lookup(__MODULE__, key) do
          [{^key, value}] ->
            {:ok, value}

          _ ->
            :error
        end
      end

      @doc """
      Returns all items stored in the underlying ETS table.

      ## Examples

          iex> MyMemoryStore.get_all()
          %{key_1: :value_1, key_2: :value_3}
      """
      @spec get_all() :: %{atom => term}
      def get_all do
        __MODULE__
        |> :ets.tab2list()
        |> Enum.into(%{})
      end

      @doc """
      Populates the underlying ETS table according to custom strategy defined in the overriden function.
      """
      @spec populate_table() :: :ok
      def populate_table, do: :ok

      @doc """
      Puts multiple items into the underlying ETS table.

      ## Examples

          iex> MyMemoryStore.put([key_1: :value_1, key_2: :value_2])
          true
      """
      @spec put(keyword) :: true
      def put(items) do
        :ets.insert(__MODULE__, items)
      end

      @doc """
      Puts the given item into the underlying ETS table.

      ## Examples

          iex> MyMemoryStore.put(:key_1, :value_1)
          true
      """
      @spec put(atom, term) :: true
      def put(key, value) do
        :ets.insert(__MODULE__, {key, value})
      end

      @doc """
      Tells whether the underlying GenServer process is alive.

      ## Examples

          iex> MyMemoryStore.running?()
          true
      """
      @spec running?() :: boolean
      def running? do
        pid = Process.whereis(__MODULE__)
        if pid, do: Process.alive?(pid), else: false
      end

      @doc """
      Tells whether the underlying ETS table exists.

      ## Examples

          iex> MyMemoryStore.table_exists?()
          true
      """
      @spec table_exists?() :: boolean
      def table_exists? do
        :ets.info(__MODULE__) != :undefined
      end

      defp create_table do
        :ets.new(__MODULE__, [:public, :named_table])
      end

      defp maybe_create_table do
        if !table_exists?(), do: create_table()
      end

      defp populate_table_from_file(path) do
        path
        |> File.read!()
        |> SerializationUtils.deserialize()
        |> Enum.each(fn {key, value} -> put(key, value) end)
      end

      defp reload_table do
        truncate_table()
        populate_table()
      end

      defp truncate_table do
        :ets.delete_all_objects(__MODULE__)
      end

      defoverridable get: 1
      defoverridable populate_table: 0
    end
  end

  @doc """
  Returns the value stored in the underlying ETS table under the given key.
  """
  @callback get(atom | binary) :: {:ok, term} | :error

  @doc """
  Populates the underlying ETS table according to custom strategy defined in the overriden function.
  """
  @callback populate_table() :: :ok
end
