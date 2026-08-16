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

    on_exit(fn -> :httpc.cancel_request(client.request_id) end)

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
