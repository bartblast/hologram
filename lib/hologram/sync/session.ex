defmodule Hologram.Sync.Session do
  @moduledoc false

  # One per connected client. It holds what that client has been told - which rows, of which
  # windows - and turns each shared round into the part of it that is this client's news.
  #
  # What it keeps is membership, never rows: the rows live once per node in the result store,
  # and a hundred sessions reading one window read that one copy.

  use GenServer, restart: :temporary

  alias Hologram.DB.QueryCache
  alias Hologram.Sync.Diff
  alias Hologram.Sync.Evaluator
  alias Hologram.Sync.Evaluators
  alias Hologram.Sync.Frame
  alias Hologram.Sync.PageWindows
  alias Hologram.Sync.ResultStore

  @doc """
  Starts a session for a client on the given `:page`, telling `:client` what changes for it.

  `:actor_user_id` is who the client is, or nil for an anonymous one - every row is checked
  against it before being sent, so what the client named as its page decides only which windows
  are kept, never what it may see of them.

  Windows a page reaches that nothing downloads are skipped rather than refused, which is how a
  client naming a page this build does not have gets a session with nothing in it.
  """
  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts) do
    {server_opts, init_opts} = Keyword.split(opts, [:name])

    GenServer.start_link(__MODULE__, init_opts, server_opts)
  end

  @impl GenServer
  def init(opts) do
    state = %{
      actor_user_id: Keyword.get(opts, :actor_user_id),
      client: Keyword.fetch!(opts, :client),
      held: %{},
      page: Keyword.fetch!(opts, :page),
      pending: MapSet.new(),
      types: %{}
    }

    {:ok, state, {:continue, :subscribe}}
  end

  @impl GenServer
  def handle_continue(:subscribe, state) do
    subscribed =
      state.page
      |> PageWindows.lookup()
      |> Enum.reduce(state, &subscribe_to_window/2)

    # A page reaching no window is complete the moment it starts: there is nothing to wait for,
    # and a client left waiting for a marker that never comes would never read its own store.
    if MapSet.size(subscribed.pending) == 0 do
      send(subscribed.client, {:sync_synced})
    end

    {:noreply, subscribed}
  end

  @impl GenServer
  def handle_info({:round, window_id, version, transactions}, state) do
    {:noreply, deliver(state, window_id, version, transactions)}
  end

  defp deliver(state, window_id, version, transactions) do
    case ResultStore.fetch(window_id, version) do
      # The round fell out of the ring before this session read it, which means it is further
      # behind than the store reaches. Catching such a client up is the reconnect path's job.
      nil ->
        state

      result ->
        held = Map.get(state.held, window_id, MapSet.new())
        deltas = Diff.deltas(result, held, state.actor_user_id, transactions)

        state
        |> send_deltas(window_id, deltas)
        |> remember(window_id, held, deltas)
        |> mark_filled(window_id)
    end
  end

  # A row is dropped only once it has left every window this client holds - one window losing it
  # while another still carries it is not news, and telling the client to drop it would take the
  # row out from under the query that still wants it.
  defp left_the_pot(state, window_id, vanished) do
    others = Map.delete(state.held, window_id)

    Enum.reject(vanished, fn id ->
      Enum.any?(others, fn {_window_id, ids} -> MapSet.member?(ids, id) end)
    end)
  end

  defp mark_filled(state, window_id) do
    pending = MapSet.delete(state.pending, window_id)

    if MapSet.size(pending) == 0 and MapSet.size(state.pending) > 0 do
      send(state.client, {:sync_synced})
    end

    %{state | pending: pending}
  end

  defp remember(state, window_id, held, deltas) do
    appeared_ids = MapSet.new(deltas.appeared, & &1.id)

    window_held =
      held
      |> MapSet.union(appeared_ids)
      |> MapSet.difference(MapSet.new(deltas.vanished))

    %{state | held: Map.put(state.held, window_id, window_held)}
  end

  defp send_deltas(state, window_id, deltas) do
    unsynced = left_the_pot(state, window_id, deltas.vanished)

    news = %{
      appeared: deltas.appeared,
      edges: deltas.edges,
      patched: deltas.patched,
      unsynced: unsynced
    }

    if news != %{appeared: [], edges: [], patched: [], unsynced: []} do
      send(state.client, {:sync_deltas, Frame.deltas(news, state.types[window_id])})
    end

    state
  end

  defp subscribe_to_window(window_id, state) do
    case Evaluators.subscribe(window_id, self()) do
      :no_window ->
        state

      {:ok, _pid, version} ->
        state
        |> remember_type(window_id)
        |> Map.update!(:pending, &MapSet.put(&1, window_id))
        |> first_round(window_id, version)
    end
  end

  # A row that left is named by the type of the window it left, since it is no longer among the
  # rows to be asked - so the type is kept from the term when the window is taken up.
  defp remember_type(state, window_id) do
    entity_type = QueryCache.window(window_id).entity

    %{state | types: Map.put(state.types, window_id, entity_type)}
  end

  defp first_round(state, window_id, 0) do
    Evaluator.round(window_id, [])

    state
  end

  defp first_round(state, window_id, version), do: deliver(state, window_id, version, [])
end
