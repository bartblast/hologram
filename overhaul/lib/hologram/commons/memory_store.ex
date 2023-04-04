defmodule Hologram.Commons.MemoryStore do
  defmacro __using__(_opts) do
    quote do
      alias Hologram.Utils

      @impl true
      def terminate(_reason, _state) do
        delete_table()
      end

      defp delete_table do
        table_name() |> :ets.delete()
      end

      def get!(key) do
        case get(key) do
          {:ok, value} ->
            value

          :error ->
            raise KeyError, message: "key #{inspect(key)} not found"
        end
      end

      def has?(key) do
        get(key) != :error
      end

      def lock(key) do
        put(key, :lock)
      end

      def maybe_stop do
        if running?(), do: stop()
      end

      def stop do
        GenServer.stop(__MODULE__)
      end
    end
  end
end
