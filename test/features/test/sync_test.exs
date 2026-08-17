defmodule HologramFeatureTests.SyncTest do
  # async: false - each test truncates the shared tables.
  use HologramFeatureTests.TestCase, async: false

  import Hologram.DB.EntityOperations, only: [create: 1, delete: 2, update: 3]

  alias Hologram.Auth.RoleGrant
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias Hologram.Entity
  alias Hologram.Sync.Evaluators
  alias Hologram.Test.SyncClient
  alias HologramFeatureTests.Entities.Document
  alias HologramFeatureTests.Entities.Folder
  alias HologramFeatureTests.Entities.Product
  alias HologramFeatureTests.Entities.Review
  alias HologramFeatureTests.Entities.User

  @base_url "http://localhost:4002"

  # Every entity table truncates, not only the documents: the client's pot is app-wide, so a row
  # left in ANY synced table by an earlier test file would arrive in this client's initial fill
  # and make "the first deltas frame" mean different things on different runs.
  #
  # The truncation must find no evaluator alive: TRUNCATE bypasses the write funnel, so no effect
  # reaches the log and nothing tells a running evaluator the rows are gone - it would keep
  # serving its pre-truncate round to every client of this test. Waiting for the drain is what
  # makes each test's first frame mean this test's rows.
  setup do
    wait_for_evaluators_to_drain()

    tables =
      Enum.map_join([Document, Folder, Review, Product, RoleGrant, User], ", ", fn entity_type ->
        ~s("hologram_data"."#{Mapper.table_name(entity_type)}")
      end)

    {:ok, _result} = Connection.query("TRUNCATE #{tables}", [])

    :ok
  end

  # A frame's data is JavaScript for the browser's interpreter - here it is asserted on as text,
  # which is what makes these tests wire tests rather than client tests.
  defp await_deltas(client) do
    {frame, client} = SyncClient.await_frame(client, "sync_deltas")

    {frame["data"], client}
  end

  # The stream is cut when the test ends, taking the server-side session and its evaluators with
  # it - a connection left open would keep them alive into the next test, serving stale rounds.
  defp connect(opts \\ []) do
    opts =
      opts
      |> Keyword.put_new(:cookie_path, "/policies")
      |> Keyword.put_new(:page, "HologramFeatureTests.PoliciesPage")

    client = SyncClient.connect(@base_url, opts)

    on_exit(fn -> SyncClient.close(client) end)

    client
  end

  defp wait_for_evaluators_to_drain(attempts_left \\ 2_000) do
    cond do
      Evaluators.live() == [] ->
        :ok

      attempts_left == 0 ->
        flunk("evaluators from an earlier test never drained")

      true ->
        Process.sleep(1)
        wait_for_evaluators_to_drain(attempts_left - 1)
    end
  end

  # The place the frame says the client has reached, which it hands back on reconnect. Read out of
  # the frame rather than built here: what it is made of is the server's business.
  defp cursor_of(data) do
    data
    |> Jason.decode!()
    |> Map.fetch!("cursor")
  end

  defp drain_initial_sync(client) do
    {page_synced, filling_client} = SyncClient.await_frame(client, "synced")
    assert page_synced["data"] =~ ~s["scope":"page"]

    {all_synced, filled_client} = SyncClient.await_frame(filling_client, "synced")
    assert all_synced["data"] =~ ~s["scope":"all"]

    filled_client
  end

  feature "fills a connecting client with the rows it may read", %{session: _session} do
    Document
    |> Entity.new(public: true, title: "seeded_before_connect")
    |> create()

    {data, _client} = await_deltas(connect())

    assert data =~ ~s["op":"put_entity"]
    assert data =~ ~s["title":"seeded_before_connect"]
  end

  feature "says the store is complete for the page and then for the app", %{session: _session} do
    client = connect()

    {page_synced, filling_client} = SyncClient.await_frame(client, "synced")
    assert page_synced["data"] =~ ~s["scope":"page"]

    {all_synced, _filled_client} = SyncClient.await_frame(filling_client, "synced")
    assert all_synced["data"] =~ ~s["scope":"all"]
  end

  feature "delivers a change as a patch carrying the fresh value", %{session: _session} do
    document =
      Document
      |> Entity.new(public: true, title: "before_patch")
      |> create()

    client = drain_initial_sync(connect())

    update(Document, document.id, %{title: "after_patch"})

    {data, _client} = await_deltas(client)

    assert data =~ ~s["op":"patch_entity"]
    assert data =~ ~s["title":"after_patch"]
  end

  feature "delivers a row created while the client watches, whole", %{session: _session} do
    client = drain_initial_sync(connect())

    Document
    |> Entity.new(public: true, title: "created_while_watching")
    |> create()

    {data, _client} = await_deltas(client)

    assert data =~ ~s["op":"put_entity"]
    assert data =~ ~s["title":"created_while_watching"]
  end

  feature "tells the client a deleted row is no longer its to hold", %{session: _session} do
    document =
      Document
      |> Entity.new(public: true, title: "to_be_deleted")
      |> create()

    client = drain_initial_sync(connect())

    delete(Document, document.id)

    {data, _client} = await_deltas(client)

    assert data =~ ~s["op":"unsync_entity"]
    assert data =~ ~s["id":"#{document.id}"]
  end

  feature "keeps a server-only value out of the frame its row travels in", %{session: _session} do
    Document
    |> Entity.new(api_token: "api_token_9xK4", public: true, title: "row_with_secret")
    |> create()

    {data, _client} = await_deltas(connect())

    # The positive artifact beside the negative one: the row IS here, its secret is not.
    assert data =~ ~s["title":"row_with_secret"]

    # Under JSON the KEY is absent, not only the value - the old wire could not say this.
    refute data =~ "api_token"
  end

  # A frame carries a place only once the client holds a whole pot, so the one this client leaves
  # with cannot come from its fill - mid-fill it holds some windows and not others, and a place
  # handed over then is a claim it could not honour. Hence the write before it leaves: it is there
  # to produce a frame after the store is complete, which is the first frame carrying a place.
  feature "tells a returning client only what moved while it was away", %{session: _session} do
    Document
    |> Entity.new(public: true, title: "held_across_the_gap")
    |> create()

    filled_client = drain_initial_sync(connect())

    Document
    |> Entity.new(public: true, title: "dated_the_store")
    |> create()

    {dating_data, departing_client} = await_deltas(filled_client)
    assert dating_data =~ ~s["title":"dated_the_store"]

    cursor = cursor_of(dating_data)
    assert is_binary(cursor)

    :ok = SyncClient.close(departing_client)

    Document
    |> Entity.new(public: true, title: "landed_while_away")
    |> create()

    {gap_data, _returned} = await_deltas(connect(cursor: cursor))

    # The whole point of the replay: what moved arrives, and what the client was filled with does
    # not. Nothing is asserted about the row it was told of just before leaving - a place names the
    # LOWER edge of the batch it came from, so replaying it again is what the design promises.
    assert gap_data =~ ~s["title":"landed_while_away"]
    refute gap_data =~ "held_across_the_gap"
  end

  feature "tells a client whose place cannot be read to start over", %{session: _session} do
    Document
    |> Entity.new(public: true, title: "sent_again_after_resync")
    |> create()

    returning_client = connect(cursor: "not a cursor")

    {resync, resyncing_client} = SyncClient.await_frame(returning_client, "sync_resync")
    assert resync["data"] =~ ~s["reason":"cursor"]

    # The marker is an instruction to discard, so what follows has to be everything again.
    {data, _refilled_client} = await_deltas(resyncing_client)
    assert data =~ ~s["title":"sent_again_after_resync"]
  end

  feature "sends an anonymous client the rows anyone may read, and no others", %{
    session: _session
  } do
    Document
    |> Entity.new(public: true, title: "public_row")
    |> create()

    Document
    |> Entity.new(title: "private_row")
    |> create()

    {data, _client} = await_deltas(connect())

    assert data =~ ~s["title":"public_row"]
    refute data =~ "private_row"
  end
end
