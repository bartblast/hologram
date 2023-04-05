defmodule Hologram.Commons.MemoryStore do
  defmacro __using__(_opts) do
    quote do
      use GenServer

      alias Hologram.Commons.MemoryStore
      alias Hologram.Commons.SerializationUtils

      @behaviour MemoryStore

      @doc """
      Starts the memory store GenServer process.

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
        case :ets.lookup(table_name(), key) do
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
        table_name()
        |> :ets.tab2list()
        |> Enum.into(%{})
      end

      def populate_table, do: :ok

      def put(items) do
        table_name() |> :ets.insert(items)
      end

      def put(key, value) do
        table_name() |> :ets.insert({key, value})
      end

      def running? do
        pid = Process.whereis(__MODULE__)
        if pid, do: Process.alive?(pid), else: false
      end

      def table_created? do
        table_name() |> :ets.info() != :undefined
      end

      defp create_table do
        table_name() |> :ets.new([:public, :named_table])
      end

      defp maybe_create_table do
        if !table_created?(), do: create_table()
      end

      defp populate_table_from_file(path) do
        path
        |> File.read!()
        |> SerializationUtils.deserialize()
        |> Enum.each(fn {key, value} -> put(key, value) end)
      end

      defp reload_table() do
        truncate_table()
        populate_table()
      end

      defp truncate_table do
        table_name() |> :ets.delete_all_objects()
      end

      defoverridable get: 1
      defoverridable populate_table: 0
    end
  end

  @callback get(atom | binary) :: {:ok, term} | :error
  @callback populate_table() :: :ok
  @callback table_name() :: atom
end
