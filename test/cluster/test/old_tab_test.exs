defmodule HologramClusterTests.OldTabTest do
  # async: false - every scenario owns the whole migrations database, and the peers it boots.
  use HologramClusterTests.TestCase, async: false

  import HologramClusterTests.MigrationHelpers

  alias Hologram.DB
  alias Hologram.DB.Connection
  alias Hologram.Test.SyncClient
  alias HologramClusterTests.Entities.Item

  @page "HologramClusterTests.SyncPage"

  # The point before the history's last file, which renames Item's `parent` to `container`.
  @old_version "20260901120000"

  # A production peer applies the chain at boot, recording the model hash after each file - what
  # a tab built at that point greets with.
  setup do
    reset_migrations_database!()

    peer = start_migration_peer(1)

    %{old_hash: recorded_hash(@old_version), peer: peer}
  end

  defp recorded_hash(version) do
    statement = ~s(SELECT "model_hash" FROM "hologram_system"."migration" WHERE "version" = $1)

    with_migrations_db(fn ->
      {:ok, %{rows: [[model_hash]]}} = Connection.query(statement, [version])

      model_hash
    end)
  end

  defp create_item(peer, attrs) do
    item = rpc(peer, DB, :create!, [Item.new(attrs)])

    item.id
  end

  # The stream is cut when the test ends, so the peer's session goes with it.
  defp connect(peer, opts) do
    client =
      SyncClient.connect(
        "http://127.0.0.1:#{peer.port}",
        Keyword.merge([cookie_path: "/sync", page: @page], opts)
      )

    on_exit(fn -> SyncClient.close(client) end)

    client
  end

  defp put_items(client) do
    {frame, client} = SyncClient.await_frame(client, "sync_deltas")

    rows =
      frame["data"]
      |> Jason.decode!()
      |> get_in(["deltas", "put_entity", "HologramClusterTests.Entities.Item"])

    {rows, client}
  end

  # Every completeness marker of the fill, up to the one saying the client holds everything.
  defp drain_fill(client) do
    {synced, client} = SyncClient.await_frame(client, "synced")

    if synced["data"] =~ ~s("scope":"all"), do: client, else: drain_fill(client)
  end

  defp record_hash(version, model_hash) do
    statement =
      ~s(UPDATE "hologram_system"."migration" SET "model_hash" = $2 WHERE "version" = $1)

    with_migrations_db(fn ->
      {:ok, _result} = Connection.query(statement, [version, model_hash])
    end)
  end

  defp create_contained_item(peer) do
    container_id = create_item(peer, %{slug: "box", title: "Box"})
    create_item(peer, %{container_id: container_id, slug: "toy", title: "Toy"})

    container_id
  end

  defp toy(rows), do: Enum.find(rows, &(&1["slug"] == "toy"))

  test "an old tab is served rows under the names its model had", %{
    old_hash: old_hash,
    peer: peer
  } do
    container_id = create_contained_item(peer)

    # The rows arriving at all say the tab is served: a tab told to reload gets no session.
    {rows, after_rows} =
      peer
      |> connect(model_hash: old_hash, synced_types: [Item])
      |> put_items()

    toy = toy(rows)

    assert toy["parent_id"] == container_id
    refute Map.has_key?(toy, "container_id")

    filled = drain_fill(after_rows)

    assert {:timeout, _client} = SyncClient.next_frame(filled, "sync_reload", 200)
  end

  # The peer's own Hologram works out the same hash for the point as the one that recorded it, so
  # only a hash the table alone holds shows the table placing the tab.
  test "an old tab is placed by the hash the migration table records", %{peer: peer} do
    container_id = create_contained_item(peer)
    record_hash(@old_version, "0ldfa5h10ned0ldfa5h10ned0ldfa5h1")

    client = connect(peer, model_hash: "0ldfa5h10ned0ldfa5h10ned0ldfa5h1", synced_types: [Item])

    {rows, _client} = put_items(client)

    assert toy(rows)["parent_id"] == container_id
  end

  test "an old tab naming no synced types is told to reload", %{old_hash: old_hash, peer: peer} do
    client = connect(peer, model_hash: old_hash)

    {frame, _client} = SyncClient.await_frame(client, "sync_reload")

    assert frame["data"] =~ ~s("reason":"model_hash")
  end

  test "a tab of a model the history doesn't know is told to reload", %{peer: peer} do
    client = connect(peer, model_hash: "0123456789abcdef0123456789abcdef", synced_types: [Item])

    {frame, _client} = SyncClient.await_frame(client, "sync_reload")

    assert frame["data"] =~ ~s("reason":"model_hash")
  end
end
