defmodule HologramClusterTests.SyncTest do
  # async: false - the peers share one database, and every scenario writes into it.
  use HologramClusterTests.TestCase, async: false

  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias Hologram.Test.SyncClient
  alias HologramClusterTests.Entities.Item
  alias HologramClusterTests.SyncHelpers

  @page "HologramClusterTests.SyncPage"

  # Long enough for a second round to have arrived if the peers were duplicating work: a dispatcher
  # polls on a 5s fallback but wakes on NOTIFY, so a repeat would land in milliseconds.
  @settle_ms 500

  setup do
    table = Mapper.table_name(Item)

    {:ok, _result} = Connection.query(~s(TRUNCATE "hologram_data"."#{table}"), [])

    :ok
  end

  defp await_deltas(client) do
    {frame, client} = SyncClient.await_frame(client, "sync_deltas")

    {frame["data"], client}
  end

  defp await_frame_data(client) do
    {data, client} = await_deltas(client)

    {Jason.decode!(data), client}
  end

  # The data of every frame up to the one making the given number final.
  defp await_final_through(client, seq) do
    {data, client} = await_deltas(client)

    if final_through?(Jason.decode!(data), seq) do
      [data]
    else
      [data | await_final_through(client, seq)]
    end
  end

  defp final_through?(frame, seq),
    do: is_integer(frame["final_seq"]) and frame["final_seq"] >= seq

  # The stream is cut when the test ends: a connection left open holds a session and its
  # evaluators alive on the peer, which the next scenario would then be served stale rounds by.
  defp connect(peer) do
    base_url = url(peer)
    client = SyncClient.connect(base_url, cookie_path: "/sync", page: @page)

    on_exit(fn -> SyncClient.close(client) end)

    client
  end

  # Peer-side work goes through SyncHelpers, which a peer can load - a test module is compiled in
  # memory on the runner and answers :undef over rpc.
  defp create_item(peer, slug, title) do
    item = rpc(peer, SyncHelpers, :create_item, [slug, title])

    item.id
  end

  defp hold_item_open(peer, slug, title) do
    rpc(peer, SyncHelpers, :hold_item_open, [slug, title, self()])
  end

  # Every completeness marker of the fill, one per entity type and then the one for everything,
  # handing back the client once the last has arrived.
  defp drain_initial_sync(client) do
    {synced, next_client} = SyncClient.await_frame(client, "synced")

    if synced["data"] =~ ~s["scope":"all"] do
      next_client
    else
      assert synced["data"] =~ ~s["scope":"types"]

      drain_initial_sync(next_client)
    end
  end

  defp url(peer), do: "http://127.0.0.1:#{peer.port}"

  describe "a transaction held open across the window" do
    # Ruling 2's guarantee, and the one claim the sandbox structurally cannot host: it runs every
    # test inside a single transaction, so two transactions racing each other never exist there.
    #
    # A save takes its serial when it first writes and holds it until it ends, so a LATER save can
    # commit FIRST. A reader advancing past what it sent would deliver the later row and then never
    # come back for the earlier one - silently, permanently. The stream sends the row that committed
    # at once, but the final limit cannot pass a save still running, so the later row's number stays
    # above it, and the reader comes back for the serial it skipped once that save commits.
    test "delivers the held write once it commits, rather than passing it by" do
      [peer_a, peer_b] = start_peers(2)

      client = drain_initial_sync(connect(peer_a))

      holder = hold_item_open(peer_a, "held-open", "Held open")

      # Killed rather than released, and only if an assertion below never gets that far: releasing
      # COMMITS, which would leave this row and its effect behind for whatever ran next, while the
      # transaction this is here to end wants ending either way. A no-op once the holder has
      # committed on its own, and once more when the peer is already gone.
      on_exit(fn -> Process.exit(holder, :kill) end)

      assert_receive {:holding, ^holder}, 5_000

      # Committed after the held write started, so with a HIGHER serial.
      create_item(peer_b, "committed-first", "Committed first")

      {committed_frame, still_waiting} = await_frame_data(client)

      [committed_row] =
        committed_frame["deltas"]["put_entity"]["HologramClusterTests.Entities.Item"]

      assert committed_row["title"] == "Committed first"

      # The row travels, its number isn't final: the save still running holds a lower serial.
      committed_seq = committed_row["server_created_seq"]
      refute final_through?(committed_frame, committed_seq)

      send(holder, :release)

      frames = await_final_through(still_waiting, committed_seq)

      # The held row arriving at all is the whole proof.
      assert Enum.any?(frames, &(&1 =~ ~s["title":"Held open"]))
    end
  end

  describe "two dispatchers, one log" do
    # Each peer reads the shared log on its own cursor, with nothing coordinated between them.
    # That is what makes both halves of this worth asserting: nothing is lost because the other
    # node "already read it", and nothing is doubled because both read the same rows.
    test "tells each client about the write exactly once" do
      [peer_a, peer_b] = start_peers(2)

      client_a = drain_initial_sync(connect(peer_a))
      client_b = drain_initial_sync(connect(peer_b))

      item_id = create_item(peer_a, "counted-once", "Counted once")

      assert {:ok, frame_a, once_told_a} = SyncClient.next_frame(client_a, "sync_deltas")
      assert frame_a["data"] =~ ~s["id":"#{item_id}"]

      assert {:ok, frame_b, once_told_b} = SyncClient.next_frame(client_b, "sync_deltas")
      assert frame_b["data"] =~ ~s["id":"#{item_id}"]

      # A settle window rather than an instant check: a duplicate would arrive late, not with the
      # first, so asking again after the round has had time to repeat is the only way to see it.
      assert {:timeout, _a} = SyncClient.next_frame(once_told_a, "sync_deltas", @settle_ms)
      assert {:timeout, _b} = SyncClient.next_frame(once_told_b, "sync_deltas", @settle_ms)
    end
  end

  describe "a write on one peer reaches a client on another" do
    # The claim only a cluster can make (rulings 2 and 3): nothing about sync is coordinated
    # between nodes. Every peer reads the shared log for its own clients, so a session served by
    # one peer must be told about a transaction that peer never executed.
    test "delivers a peer's write to a client connected to the other peer" do
      [peer_a, peer_b] = start_peers(2)

      client = drain_initial_sync(connect(peer_a))

      item_id = create_item(peer_b, "written-on-b", "Written on peer B")

      {data, _client} = await_deltas(client)

      assert data =~ ~s[put_entity":{"HologramClusterTests.Entities.Item":]
      assert data =~ ~s["title":"Written on peer B"]
      assert data =~ ~s["id":"#{item_id}"]
    end

    # The other direction is not the same test: a listener that works one way and not the other
    # is exactly the kind of asymmetry one direction cannot show.
    test "delivers the write in the other direction too" do
      [peer_a, peer_b] = start_peers(2)

      client = drain_initial_sync(connect(peer_b))

      item_id = create_item(peer_a, "written-on-a", "Written on peer A")

      {data, _client} = await_deltas(client)

      assert data =~ ~s[put_entity":{"HologramClusterTests.Entities.Item":]
      assert data =~ ~s["title":"Written on peer A"]
      assert data =~ ~s["id":"#{item_id}"]
    end
  end
end
