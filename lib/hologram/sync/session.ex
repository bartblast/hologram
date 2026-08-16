defmodule Hologram.Sync.Session do
  @moduledoc false

  # One per connected client. It holds what that client has been told - which rows, of which
  # windows - and turns each shared round into the part of it that is this client's news.
  #
  # What it keeps is membership, never rows: the rows live once per node in the result store,
  # and a hundred sessions reading one window read that one copy.
  #
  # A client is given every window this build downloads, not only the ones its page reads: a page
  # it navigates to is then answered from what it already has, with no server in the way. The page
  # decides ORDER - its own windows fill first, the rest follow - so what the client is looking at
  # is ready first and the rest arrives while it reads.

  use GenServer, restart: :temporary

  alias Hologram.DB.QueryCache
  alias Hologram.Sync.Catchup
  alias Hologram.Sync.Diff
  alias Hologram.Sync.Evaluator
  alias Hologram.Sync.Evaluators
  alias Hologram.Sync.Frame
  alias Hologram.Sync.PageWindows
  alias Hologram.Sync.ResultStore

  @doc """
  Starts a session for a client on the given `:page`, telling `:client` what changes for it.

  `:actor_user_id` is who the client is, or nil for an anonymous one - every row is checked
  against it before being sent, so what the client named as its page decides only the order the
  windows fill in, never what it may see of them.

  `:gap` is what a returning client missed - absent for one arriving with nothing, in which case
  every row it may see is sent. Given a gap, the client keeps what it already holds and is told
  only about the rows the gap names. Whether a gap can be had at all is decided before the session
  starts, since it is a question about the log rather than about this client.

  Windows that nothing downloads are skipped rather than refused, which is how a client naming a
  page this build does not have still gets the rest of the build's windows.
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
      announced: MapSet.new(),
      client: Keyword.fetch!(opts, :client),
      gap: Keyword.get(opts, :gap),
      held: %{},
      page: Keyword.fetch!(opts, :page),
      page_windows: MapSet.new(),
      pending: MapSet.new(),
      touched: %{},
      types: %{}
    }

    {:ok, state, {:continue, :subscribe}}
  end

  @impl GenServer
  def handle_continue(:subscribe, state) do
    page_window_ids = PageWindows.lookup(state.page)
    background_window_ids = PageWindows.all() -- page_window_ids
    window_ids = page_window_ids ++ background_window_ids

    # Every window counts as outstanding before any of them is taken up, so one that fills while
    # the others are still being taken up cannot empty the set and say the client has everything.
    seeded = %{
      state
      | page_windows: MapSet.new(page_window_ids),
        pending: MapSet.new(window_ids)
    }

    # A client with nothing to wait for is told so at once: one left waiting for a marker that
    # never comes would never read its own store.
    subscribed = Enum.reduce(window_ids, announce(seeded), &subscribe_to_window/2)

    {:noreply, subscribed}
  end

  @impl GenServer
  def handle_info(:behind_the_ring, state) do
    {:stop, :behind_the_ring, state}
  end

  def handle_info({:round, window_id, version, transactions}, state) do
    {:noreply, deliver(state, window_id, version, transactions)}
  end

  defp deliver(state, window_id, version, transactions) do
    case ResultStore.fetch(window_id, version) do
      # The round fell out of the ring before this session read it, so this client is further
      # behind than the store reaches - the same cliff as coming back to a log that no longer
      # covers you, and answered the same way: the connection is cut and the client comes back
      # through the doors like any returning one. Cutting is what the session HAS to do rather
      # than filling again in place, because what it holds is what the client was told, and a
      # round it cannot read leaves it unable to say what that still is.
      #
      # Deferred rather than stopped here, so every caller of this can carry on returning state.
      nil ->
        send(self(), :behind_the_ring)

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

  # A client being caught up is told nothing until it is: what it holds is stale until the gap
  # lands, and a marker saying otherwise would have it read a store that lies. Once every window
  # has reported, what the client may see is known, and the gap can be spoken.
  defp announce(state) do
    cond do
      not replaying?(state) ->
        announce_scopes(state)

      Enum.empty?(state.pending) ->
        state
        |> catch_up()
        |> announce_scopes()

      true ->
        state
    end
  end

  # Two scopes rather than one marker per window: what a client needs to know is whether it can
  # answer a page from its own store, and window ids are the server's business - they never cross
  # the wire. `:page` means the page the client is on is answerable, `:all` means every page is.
  defp announce_scopes(state) do
    state
    |> announce_scope(:page)
    |> announce_scope(:all)
  end

  defp announce_scope(state, scope) do
    filled? =
      state
      |> outstanding(scope)
      |> Enum.empty?()

    if filled? and not MapSet.member?(state.announced, scope) do
      send(state.client, {:sync_synced, scope})

      %{state | announced: MapSet.put(state.announced, scope)}
    else
      state
    end
  end

  # What the client missed, told from the rows as they stand now rather than from the log's own
  # account of them. Everything it holds that the gap never touched is still true, and is left
  # alone - which is the whole saving over sending it the lot.
  defp catch_up(state) do
    deltas = Catchup.deltas(state.gap, state.touched)

    if deltas != [] do
      send(state.client, {:sync_deltas, deltas})
    end

    %{state | gap: nil, touched: %{}}
  end

  defp mark_filled(state, window_id) do
    filled = %{state | pending: MapSet.delete(state.pending, window_id)}

    announce(filled)
  end

  defp outstanding(state, :all), do: state.pending

  defp outstanding(state, :page) do
    MapSet.intersection(state.pending, state.page_windows)
  end

  defp remember(state, window_id, held, deltas) do
    appeared_ids = MapSet.new(deltas.appeared, & &1.id)

    window_held =
      held
      |> MapSet.union(appeared_ids)
      |> MapSet.difference(MapSet.new(deltas.vanished))

    %{state | held: Map.put(state.held, window_id, window_held)}
  end

  defp replaying?(state), do: state.gap != nil

  # While a client is being caught up nothing goes out, so the gap cannot be undone by a round
  # that reaches it first. What the rounds are read for is the rows the gap names - and only
  # those, so what is held here is bounded by what moved rather than by what the client holds.
  defp remember_touched(state, deltas) do
    touched_ids = MapSet.new(state.gap, & &1.entity_id)

    rows =
      deltas.patched
      |> Enum.map(fn {row, _patch} -> row end)
      |> Enum.concat(deltas.appeared)
      |> Enum.filter(&MapSet.member?(touched_ids, &1.id))
      |> Map.new(&{&1.id, &1})

    %{state | touched: Map.merge(state.touched, rows)}
  end

  defp send_deltas(state, window_id, deltas) do
    if replaying?(state) do
      remember_touched(state, deltas)
    else
      tell(state, window_id, deltas)
    end
  end

  defp tell(state, window_id, deltas) do
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
      # Nothing downloads it, so nothing will ever arrive for it - which is as filled as it will
      # ever be, and waiting on it would leave the client waiting forever.
      :no_window ->
        mark_filled(state, window_id)

      {:ok, _pid, version} ->
        state
        |> remember_type(window_id)
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
