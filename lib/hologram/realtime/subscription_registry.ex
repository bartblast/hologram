defmodule Hologram.Realtime.SubscriptionRegistry do
  @moduledoc false

  use GenServer

  @table_name :hologram_subscriptions

  @doc """
  Returns the name of the ETS table that backs the registry.
  """
  @spec ets_table_name() :: atom
  def ets_table_name, do: @table_name

  @doc """
  Registers an SSE connection for the given `instance_id` by inserting an entry
  into the ETS table. The registry monitors `sse_pid` so the entry can be
  cleaned up when the pid goes down.

  Inserted entry shape per `instance_id`:

      %{
        sse_pid: pid,
        sse_ref: reference
      }
  """
  @spec register(String.t(), pid) :: :ok
  def register(instance_id, sse_pid) do
    GenServer.call(__MODULE__, {:register, instance_id, sse_pid})
  end

  @doc """
  Starts the subscription registry process.
  """
  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl GenServer
  def init(_opts) do
    :ets.new(@table_name, [:set, :public, :named_table, read_concurrency: true])

    {:ok, %{}}
  end

  @impl GenServer
  def handle_call({:register, instance_id, sse_pid}, _from, refs) do
    sse_ref = Process.monitor(sse_pid)
    entry = %{sse_pid: sse_pid, sse_ref: sse_ref}
    :ets.insert(@table_name, {instance_id, entry})

    {:reply, :ok, Map.put(refs, sse_ref, instance_id)}
  end

  @impl GenServer
  def handle_info({:DOWN, ref, :process, _pid, _reason}, refs) do
    case Map.pop(refs, ref) do
      {nil, refs} ->
        {:noreply, refs}

      {instance_id, new_refs} ->
        :ets.delete(@table_name, instance_id)
        {:noreply, new_refs}
    end
  end
end
