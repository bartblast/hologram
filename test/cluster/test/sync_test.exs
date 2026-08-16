defmodule HologramClusterTests.SyncTest do
  # async: false - the peers share one database, and every scenario writes into it.
  use HologramClusterTests.TestCase, async: false

  import Hologram.DB.EntityOperations, only: [create: 1]

  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias Hologram.Entity
  alias Hologram.Test.SyncClient
  alias HologramClusterTests.Entities.Item

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

  # The stream is cut when the test ends: a connection left open holds a session and its
  # evaluators alive on the peer, which the next scenario would then be served stale rounds by.
  defp connect(peer) do
    base_url = url(peer)
    client = SyncClient.connect(base_url, cookie_path: "/sync", page: @page)

    on_exit(fn -> SyncClient.close(client) end)

    client
  end

  defp create_item(peer, slug, title) do
    rpc(peer, __MODULE__, :create_item_locally, [slug, title])
  end

  @doc false
  def create_item_locally(slug, title) do
    item =
      Item
      |> Entity.new(slug: slug, title: title)
      |> create()

    item.id
  end

  defp drain_initial_sync(client) do
    {page_synced, filling_client} = SyncClient.await_frame(client, "synced")
    assert page_synced["data"] =~ ~s["scope":"page"]

    {all_synced, filled_client} = SyncClient.await_frame(filling_client, "synced")
    assert all_synced["data"] =~ ~s["scope":"all"]

    filled_client
  end

  defp url(peer), do: "http://127.0.0.1:#{peer.port}"

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

      assert data =~ ~s["op":"put_entity"]
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

      assert data =~ ~s["op":"put_entity"]
      assert data =~ ~s["title":"Written on peer A"]
      assert data =~ ~s["id":"#{item_id}"]
    end
  end
end
