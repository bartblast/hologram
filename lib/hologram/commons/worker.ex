defmodule Hologram.Commons.Worker do
  defmacro __using__(_opts) do
    quote do
      use GenServer

      @behaviour Hologram.Commons.Worker

      def run do
        start_link(nil)
      end

      def start_link(_opts) do
        GenServer.start_link(__MODULE__, [], name: __MODULE__)
      end

      @impl true
      def init(_state) do
        Process.send_after(self(), :work, 0)
        {:ok, []}
      end

      def enqueue(job) do
        GenServer.call(__MODULE__, {:enqueue, job})
      end

      @impl true
      def handle_call({:enqueue, job}, _from, queue) do
        {:reply, nil, queue ++ [job]}
      end

      @impl true
      def handle_info(:work, []) do
        Process.send_after(self(), :work, 100)
        {:noreply, []}
      end

      @impl true
      def handle_info(:work, [job | queue_tail]) do
        perform(job)
        Process.send_after(self(), :work, 0)
        {:noreply, queue_tail}
      end
    end
  end

  @callback perform(any()) :: any()
end
