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
  Returns `{session_id, user_id}` for the given `instance_id`, or `nil` if no
  entry exists. Reads ETS directly to bypass the registry's GenServer mailbox.
  """
  @spec identity_of(String.t()) :: {term | nil, term | nil} | nil
  def identity_of(instance_id) do
    case :ets.lookup(@table_name, instance_id) do
      [{^instance_id, entry}] -> {entry.session_id, entry.user_id}
      [] -> nil
    end
  end

  @doc """
  Registers an SSE connection for the given `instance_id` by inserting an entry
  into the ETS table. The registry monitors `sse_pid` so the entry can be
  cleaned up when the pid goes down.

  Inserted entry shape per `instance_id`:

      %{
        bindings:   %{ {channel, cid} => authorizing_user_id | nil },
        session_id: term | nil,
        sse_pid:    pid,
        sse_ref:    reference,
        user_id:    term | nil
      }

  `bindings` is initialized to `%{}` and populated later via `transition/4` /
  `update/4`. `session_id` and `user_id` are initialized to `nil` and populated
  later via the identity-update helpers.
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

  @doc """
  Transitions the registry's binding set for the given `instance_id` to
  `new_bindings`. When a registry entry exists, the entry's `bindings` field is
  replaced and each binding is tagged with `authorizing_user_id` (the current
  authenticated user_id at handler time, or `nil` for anonymous).

  Returns `{add_keys, drop_keys}` - the diff between `new_bindings` and
  `client_supplied_keys`, used to drive the client-side `{adds, drops}`
  response payload.
  """
  @spec transition(String.t(), [{any, String.t()}], [{any, String.t()}], term | nil) ::
          {[{any, String.t()}], [{any, String.t()}]}
  def transition(instance_id, new_bindings, client_supplied_keys, authorizing_user_id) do
    GenServer.call(
      __MODULE__,
      {:transition, instance_id, new_bindings, client_supplied_keys, authorizing_user_id}
    )
  end

  @doc """
  Updates the `session_id` and `user_id` fields of the entry for the given
  `instance_id`. No-op when no entry exists.
  """
  @spec update_identity(String.t(), term | nil, term | nil) :: :ok
  def update_identity(instance_id, session_id, user_id) do
    GenServer.call(__MODULE__, {:update_identity, instance_id, session_id, user_id})
  end

  @impl GenServer
  def init(_opts) do
    :ets.new(@table_name, [:set, :public, :named_table, read_concurrency: true])

    {:ok, %{}}
  end

  @impl GenServer
  def handle_call({:register, instance_id, sse_pid}, _from, refs) do
    sse_ref = Process.monitor(sse_pid)

    entry = %{
      bindings: %{},
      session_id: nil,
      sse_pid: sse_pid,
      sse_ref: sse_ref,
      user_id: nil
    }

    :ets.insert(@table_name, {instance_id, entry})

    {:reply, :ok, Map.put(refs, sse_ref, instance_id)}
  end

  @impl GenServer
  def handle_call(
        {:transition, instance_id, new_bindings, client_supplied_keys, authorizing_user_id},
        _from,
        refs
      ) do
    new_keys_set = MapSet.new(new_bindings)
    client_keys_set = MapSet.new(client_supplied_keys)

    add_keys =
      new_keys_set
      |> MapSet.difference(client_keys_set)
      |> MapSet.to_list()

    drop_keys =
      client_keys_set
      |> MapSet.difference(new_keys_set)
      |> MapSet.to_list()

    case :ets.lookup(@table_name, instance_id) do
      [{^instance_id, entry}] ->
        new_bindings_map = Map.new(new_bindings, fn key -> {key, authorizing_user_id} end)
        :ets.insert(@table_name, {instance_id, %{entry | bindings: new_bindings_map}})

      [] ->
        :noop
    end

    {:reply, {add_keys, drop_keys}, refs}
  end

  @impl GenServer
  def handle_call({:update_identity, instance_id, session_id, user_id}, _from, refs) do
    case :ets.lookup(@table_name, instance_id) do
      [{^instance_id, entry}] ->
        new_entry = %{entry | session_id: session_id, user_id: user_id}
        :ets.insert(@table_name, {instance_id, new_entry})

      [] ->
        :noop
    end

    {:reply, :ok, refs}
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
