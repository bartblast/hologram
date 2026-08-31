defmodule HologramFeatureTests.SyncTest do
  # async: false - each test truncates the shared tables.
  use HologramFeatureTests.TestCase, async: false

  import Hologram.DB.EntityOperations, only: [delete: 2, update: 3]

  alias Hologram.Auth.RoleGrant
  alias Hologram.DB
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias Hologram.Test.SyncClient
  alias HologramFeatureTests.Entities.Document
  alias HologramFeatureTests.Entities.Folder
  alias HologramFeatureTests.Entities.Note
  alias HologramFeatureTests.Entities.Product
  alias HologramFeatureTests.Entities.Review
  alias HologramFeatureTests.Entities.User

  @base_url "http://localhost:4002"

  # Every entity table truncates, not only the documents: the client's pot is app-wide, so a row
  # left in ANY synced table by an earlier test file would arrive in this client's initial fill
  # and make "the first deltas frame" mean different things on different runs.
  setup do
    await_evaluator_drain()

    tables =
      Enum.map_join(
        [Document, Folder, Note, Review, Product, RoleGrant, User],
        ", ",
        fn entity_type ->
          ~s("hologram_data"."#{Mapper.table_name(entity_type)}")
        end
      )

    {:ok, _result} = Connection.query("TRUNCATE #{tables}", [])

    :ok
  end

  # Waits for the frame carrying what this test did, passing over the ones it did not ask for.
  #
  # A frame's data is JavaScript for the browser's interpreter - here it is asserted on as text,
  # which is what makes these tests wire tests rather than client tests.
  #
  # A client is told about an effect for a row it already holds, which is how a row written before
  # it connected reaches it a second time: filled from the rows, then patched with what the log
  # says moved. Idempotent by design, and never a reason for the frame a test is waiting on to
  # arrive first - so a test names what it is waiting for rather than taking the next one.
  defp await_deltas_carrying(client, text) do
    await_deltas_carrying(client, text, System.monotonic_time(:millisecond) + 5_000)
  end

  defp await_deltas_carrying(client, text, deadline) do
    timeout = deadline - System.monotonic_time(:millisecond)

    if timeout <= 0 do
      flunk("no sync_deltas frame carrying #{inspect(text)} arrived")
    end

    case SyncClient.next_frame(client, "sync_deltas", timeout) do
      {:ok, frame, client} ->
        if String.contains?(frame["data"], text) do
          {frame["data"], client}
        else
          await_deltas_carrying(client, text, deadline)
        end

      {:timeout, _client} ->
        flunk("no sync_deltas frame carrying #{inspect(text)} arrived")
    end
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
    %{public: true, title: "seeded_before_connect"}
    |> Document.new()
    |> DB.create!()

    {data, _client} = await_deltas_carrying(connect(), ~s["title":"seeded_before_connect"])

    assert data =~ ~s["put_entity":]
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
      %{public: true, title: "before_patch"}
      |> Document.new()
      |> DB.create!()

    client = drain_initial_sync(connect())

    update(Document, document.id, %{title: "after_patch"})

    {data, _client} = await_deltas_carrying(client, ~s["title":"after_patch"])

    assert data =~ ~s["patch_entity":]
  end

  # The wire half of the revisions path: a patch carries an entry for each column it names, which
  # is what the client writes over its own map rather than being sent a whole one.
  feature "carries the revisions of a patched column", %{session: _session} do
    document =
      %{public: true, title: "before_revision_patch"}
      |> Document.new()
      |> DB.create!()

    client = drain_initial_sync(connect())

    update(Document, document.id, %{title: "after_revision_patch"})

    {data, _client} = await_deltas_carrying(client, ~s["$revisions":{"title":])

    patched =
      data
      |> Jason.decode!()
      |> get_in(["deltas", "patch_entity", "HologramFeatureTests.Entities.Document"])

    reloaded = DB.read(Document, document.id)

    assert [%{"$revisions" => revisions, "id" => patched_id}] = patched
    assert patched_id == document.id
    assert revisions == %{"title" => reloaded.__meta__.revisions.title}
  end

  # The defect this spec pins: membership must cover the window's whole REACH, so a row no window
  # roots - the folder is reachable only through the document window's include - still receives
  # its own patches. Rooted-everywhere fixtures kept the hole green for a whole step.
  feature "patches a row reached only through an include", %{session: _session} do
    folder =
      %{name: "folder_before_patch", public: true}
      |> Folder.new()
      |> DB.create!()

    %{folder_id: folder.id, public: true, title: "reaches_the_folder"}
    |> Document.new()
    |> DB.create!()

    client = drain_initial_sync(connect())

    update(Folder, folder.id, %{name: "folder_after_patch"})

    {data, _client} = await_deltas_carrying(client, ~s["name":"folder_after_patch"])

    # Read out of the frame rather than matched against its text: what else shares the round is
    # not this test's business. A round reports every member of the window's reach, so the
    # document that reaches this folder can be grouped beside it - and being grouped FIRST, since
    # the types are keyed by module name, would break a match that expects to find the folder
    # right after the op.
    folder_rows =
      data
      |> Jason.decode!()
      |> get_in(["deltas", "patch_entity", "HologramFeatureTests.Entities.Folder"])

    assert [%{"id" => patched_id, "name" => "folder_after_patch"}] = folder_rows
    assert patched_id == folder.id
  end

  feature "delivers a row created while the client watches, whole", %{session: _session} do
    client = drain_initial_sync(connect())

    %{public: true, title: "created_while_watching"}
    |> Document.new()
    |> DB.create!()

    {data, _client} = await_deltas_carrying(client, ~s["title":"created_while_watching"])

    assert data =~ ~s["put_entity":]
  end

  feature "tells the client a deleted row is no longer its to hold", %{session: _session} do
    document =
      %{public: true, title: "to_be_deleted"}
      |> Document.new()
      |> DB.create!()

    client = drain_initial_sync(connect())

    delete(Document, document.id)

    {data, _client} = await_deltas_carrying(client, ~s["unsync_entity":])

    # An unsync travels as the bare id in its type's list, so the id alone is the whole delta -
    # read out of the frame rather than matched against its text, which a delta of any shape at
    # all would satisfy as long as the id appeared somewhere in it.
    unsynced_ids =
      data
      |> Jason.decode!()
      |> get_in(["deltas", "unsync_entity", "HologramFeatureTests.Entities.Document"])

    assert unsynced_ids == [document.id]
  end

  feature "keeps a server-only value out of the frame its row travels in", %{session: _session} do
    %{api_token: "api_token_9xK4", public: true, title: "row_with_secret"}
    |> Document.new()
    |> DB.create!()

    # Waiting for the row is the positive artifact beside the negative one: this is the frame the
    # row travelled in, so what it does not carry is what was kept from it.
    {data, _client} = await_deltas_carrying(connect(), ~s["title":"row_with_secret"])

    # Under JSON the KEY is absent, not only the value - the old wire could not say this.
    refute data =~ "api_token"
  end

  # A frame carries a place only once the client holds a whole pot, so the one this client leaves
  # with cannot come from its fill - mid-fill it holds some windows and not others, and a place
  # handed over then is a claim it could not honour. Hence the write before it leaves: it is there
  # to produce a frame after the store is complete, which is the first frame carrying a place.
  feature "tells a returning client only what moved while it was away", %{session: _session} do
    %{public: true, title: "held_across_the_gap"}
    |> Document.new()
    |> DB.create!()

    filled_client = drain_initial_sync(connect())

    %{public: true, title: "dated_the_store"}
    |> Document.new()
    |> DB.create!()

    {dating_data, departing_client} =
      await_deltas_carrying(filled_client, ~s["title":"dated_the_store"])

    cursor = cursor_of(dating_data)
    assert is_binary(cursor)

    :ok = SyncClient.close(departing_client)

    %{public: true, title: "landed_while_away"}
    |> Document.new()
    |> DB.create!()

    {gap_data, _returned} =
      await_deltas_carrying(connect(cursor: cursor), ~s["title":"landed_while_away"])

    # The whole point of the replay: what moved arrives, and what the client was filled with does
    # not. Nothing is asserted about the row it was told of just before leaving - a place names the
    # LOWER edge of the batch it came from, so replaying it again is what the design promises.
    assert gap_data =~ ~s["title":"landed_while_away"]
    refute gap_data =~ "held_across_the_gap"
  end

  # A row can be readable because ANOTHER row is - `Document` takes `ReadableThroughFolder`, so a
  # document is readable when its folder is. Nothing writes to the document when the folder moves,
  # so the log never names it and the replay would pass over it.
  #
  # What isolates the folder's rule in both features below: the document is `public: false` and
  # nobody holds a role on it, so `PubliclyReadable` and `Editable` admit nothing and the folder is
  # the only thing that can. Each asserts that rather than assuming it - this one by requiring the
  # document in the fill, its mirror by requiring it absent.
  feature "drops what a folder made private no longer admits", %{session: _session} do
    folder =
      %{name: "folder_open_then_shut", public: true}
      |> Folder.new()
      |> DB.create!()

    document =
      %{folder_id: folder.id, public: false, title: "held_through_its_folder"}
      |> Document.new()
      |> DB.create!()

    # Awaited BEFORE draining, since drain_initial_sync/1 passes over the deltas frames and drops
    # them - the fill's own content can be read here and nowhere after. Its arrival is what proves
    # the folder's rule is admitting it, which is what the folder going private then takes away.
    {_fill_data, filling_client} =
      await_deltas_carrying(connect(), ~s["title":"held_through_its_folder"])

    filled_client = drain_initial_sync(filling_client)

    # A frame carries a place only once the store is whole, so the client is given something to
    # be told about after its fill - that frame is the first one carrying a cursor.
    %{public: true, title: "dated_the_store_before_shutting"}
    |> Document.new()
    |> DB.create!()

    {dating_data, departing_client} =
      await_deltas_carrying(filled_client, ~s["title":"dated_the_store_before_shutting"])

    cursor = cursor_of(dating_data)
    :ok = SyncClient.close(departing_client)

    update(Folder, folder.id, %{public: false})

    {gap_data, _returned} = await_deltas_carrying(connect(cursor: cursor), document.id)

    # Fails against the framework before this issue: the gap names the folder alone, so the only
    # unsync arriving is the folder's own.
    unsynced_ids =
      gap_data
      |> Jason.decode!()
      |> get_in(["deltas", "unsync_entity", "HologramFeatureTests.Entities.Document"])

    assert unsynced_ids == [document.id]
  end

  feature "hands over what a folder made public now admits", %{session: _session} do
    folder =
      %{name: "folder_shut_then_open"}
      |> Folder.new()
      |> DB.create!()

    document =
      %{folder_id: folder.id, public: false, title: "revealed_by_its_folder"}
      |> Document.new()
      |> DB.create!()

    %{public: true, title: "visible_all_along"}
    |> Document.new()
    |> DB.create!()

    # The anchor is the positive artifact beside the negative one: this is the frame the document
    # WOULD have travelled in, so its absence there is the client never having held it - which is
    # what makes the put_entity below a row being revealed rather than one being sent again.
    {fill_data, filling_client} =
      await_deltas_carrying(connect(), ~s["title":"visible_all_along"])

    refute fill_data =~ "revealed_by_its_folder"

    filled_client = drain_initial_sync(filling_client)

    %{public: true, title: "dated_the_store_before_opening"}
    |> Document.new()
    |> DB.create!()

    {dating_data, departing_client} =
      await_deltas_carrying(filled_client, ~s["title":"dated_the_store_before_opening"])

    cursor = cursor_of(dating_data)
    :ok = SyncClient.close(departing_client)

    update(Folder, folder.id, %{public: true})

    {gap_data, _returned} =
      await_deltas_carrying(connect(cursor: cursor), ~s["title":"revealed_by_its_folder"])

    # Fails against the framework before this issue: the gap names the folder alone, so nothing
    # names the document at all.
    put_documents =
      gap_data
      |> Jason.decode!()
      |> get_in(["deltas", "put_entity", "HologramFeatureTests.Entities.Document"])

    assert [%{"id" => put_id, "title" => "revealed_by_its_folder"}] = put_documents
    assert put_id == document.id
  end

  feature "tells a client whose place cannot be read to start over", %{session: _session} do
    %{public: true, title: "sent_again_after_resync"}
    |> Document.new()
    |> DB.create!()

    returning_client = connect(cursor: "not a cursor")

    {resync, resyncing_client} = SyncClient.await_frame(returning_client, "sync_resync")
    assert resync["data"] =~ ~s["reason":"cursor"]

    # The marker is an instruction to discard, so what follows has to be everything again.
    {data, _refilled_client} =
      await_deltas_carrying(resyncing_client, ~s["title":"sent_again_after_resync"])

    assert data =~ ~s["put_entity":]
  end

  feature "sends an anonymous client the rows anyone may read, and no others", %{
    session: _session
  } do
    %{public: true, title: "public_row"}
    |> Document.new()
    |> DB.create!()

    %{title: "private_row"}
    |> Document.new()
    |> DB.create!()

    # The frame the readable row travelled in, so what it does not carry is what a visitor was not
    # shown rather than what happened to arrive later.
    {data, _client} = await_deltas_carrying(connect(), ~s["title":"public_row"])

    refute data =~ "private_row"
  end
end
