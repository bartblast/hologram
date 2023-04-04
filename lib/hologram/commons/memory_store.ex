defmodule Hologram.Commons.MemoryStore do
  defmacro __using__(_opts) do
    quote do
      use GenServer

      alias Hologram.Commons.MemoryStore
      alias Hologram.Commons.SerializationUtils

      @behaviour MemoryStore

      def run do
        GenServer.start_link(__MODULE__, nil, name: __MODULE__)
      end

      @impl GenServer
      def init(_arg) do
        maybe_create_table()
        reload_table()
        {:ok, nil}
      end

      def get(key) do
        case :ets.lookup(table_name(), key) do
          [{^key, value}] ->
            {:ok, value}

          _ ->
            :error
        end
      end

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
