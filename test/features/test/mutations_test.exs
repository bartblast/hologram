defmodule HologramFeatureTests.MutationsTest do
  # async: false - each test truncates the shared tables.
  use HologramFeatureTests.TestCase, async: false

  alias Hologram.Auth.RoleGrant
  alias Hologram.DB
  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias Hologram.Entity
  alias Hologram.Entity.Model
  alias Hologram.Runtime.ReplicaIdentity
  alias HologramFeatureTests.Entities.Item
  alias HologramFeatureTests.Entities.Note
  alias HologramFeatureTests.Entities.User
  alias HologramFeatureTests.Jobs.RestockItem
  alias HologramFeatureTests.MutationsPage

  # Every table truncates in one statement: the role grant table's foreign keys to the user table
  # and the job's to the item table make Postgres reject truncating a referenced table alone.
  setup do
    await_evaluator_drain()

    tables =
      Enum.map_join([Item, Note, RestockItem, RoleGrant, User], ", ", fn entity_type ->
        ~s("hologram_data"."#{Mapper.table_name(entity_type)}")
      end)

    {:ok, _result} = Connection.query("TRUNCATE #{tables}", [])

    :ok
  end

  # Polls for the answer the posted batch left behind, and clears it so a second post in the same
  # test cannot read the first one's.
  defp await_response(session) do
    Enum.reduce_while(1..100, nil, fn _attempt, _acc ->
      case script_result(session, "return globalThis.__mutationResponse;") do
        nil ->
          Process.sleep(50)
          {:cont, nil}

        response ->
          execute_script(session, "globalThis.__mutationResponse = null;")
          {:halt, response}
      end
    end)
  end

  defp create_item(stock) do
    %{name: "widget", stock: stock}
    |> Item.new()
    |> DB.create!()
  end

  # A create of a job, spelled as an ordinary create - which is what a job is on the wire.
  defp create_restock_write(item_id, amount) do
    %{
      "op" => "create",
      "type" => inspect(RestockItem),
      "id" => Entity.generate_id(),
      "data" => %{"amount" => amount, "item_id" => item_id},
      "claim" => nil,
      "stamp" => System.os_time(:millisecond) * 1024
    }
  end

  defp create_note_write(author_id, body) do
    %{
      "op" => "create",
      "type" => inspect(Note),
      "id" => Entity.generate_id(),
      "data" => %{"body" => body, "author_id" => author_id},
      "claim" => nil,
      "stamp" => System.os_time(:millisecond) * 1024
    }
  end

  defp log_in(session) do
    session
    |> visit(MutationsPage)
    |> click(button("Log in"))
    |> assert_text(css("#result"), "logged_in")
  end

  # Proves the DOM changed without the page being fetched again - a reload would take this marker
  # with it, so a passing assertion after one would say nothing.
  defp mark_this_page_load(session) do
    execute_script(session, "globalThis.__thisPageLoad = 'held';")
  end

  defp assert_same_page_load(session) do
    assert_script_result(session, "return globalThis.__thisPageLoad;", "held")
  end

  # What the page sends as its replica_id, and so what the record is keyed by.
  defp page_replica_id(session) do
    script_result(session, "return globalThis.Hologram.replicaId;")
  end

  # The signed statement the page was given beside its replica id.
  defp page_replica_token(session) do
    script_result(session, "return globalThis.Hologram.replicaToken;")
  end

  # A move carries no data and no based_on: a delta is never merged, so there is no revision for it
  # to be based on, and a wall-clock stamp is enough.
  defp move_stock_write(id, amount) do
    %{
      "op" => "update",
      "type" => inspect(Item),
      "id" => id,
      "deltas" => %{"stock" => amount},
      "claim" => nil,
      "stamp" => System.os_time(:millisecond) * 1024
    }
  end

  defp pin_note_write(id) do
    %{
      "op" => "update",
      "type" => inspect(Note),
      "id" => id,
      "data" => %{"pinned" => true},
      "based_on" => %{},
      "claim" => ["authorize", "pin"],
      "stamp" => System.os_time(:millisecond) * 1024
    }
  end

  # The batch is built and sent IN THE BROWSER, from the identity and the model hash the runtime
  # already holds - so what this exercises is the endpoint a client will really reach, headers
  # included, rather than a request assembled in the test process.
  defp post_batch(session, seq, writes, identity \\ nil) do
    {replica_id_js, replica_token_js} =
      case identity do
        nil ->
          {"globalThis.Hologram.replicaId", "globalThis.Hologram.replicaToken"}

        %{replica_id: replica_id, replica_token: replica_token} ->
          {Jason.encode!(replica_id), Jason.encode!(replica_token)}
      end

    script = """
    const payload = {
      instance_id: globalThis.Hologram.instanceId,
      replica_id: #{replica_id_js},
      replica_token: #{replica_token_js},
      seq: #{seq},
      model_hash: globalThis.Hologram.sync.modelHash,
      writes: #{Jason.encode!(writes)}
    };

    fetch("/hologram/mutation", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Csrf-Token": globalThis.Hologram.csrfToken
      },
      body: JSON.stringify(payload)
    })
      .then((response) => response.ok ? response.json() : {status: response.status})
      .then((json) => { globalThis.__mutationResponse = json; });
    """

    execute_script(session, script)
  end

  # What the server kept of this browser's batches, scoped to the browser that sent them - the
  # record is a shared table, and each of these features asks only about its own page's batches.
  defp record_rows(replica_id) do
    statement = """
    SELECT "actor_id", "result", "envelope" FROM "hologram_system"."mutation"
    WHERE "replica_id" = $1 ORDER BY "seq"
    """

    {:ok, %Postgrex.Result{rows: rows}} = Connection.query(statement, [replica_id])

    Enum.map(rows, fn [actor_id, result, envelope] ->
      %{actor_id: Codec.decode(actor_id, :uuid), envelope: envelope, result: result}
    end)
  end

  defp session_user do
    User
    |> DB.read()
    |> Enum.find(&(&1.email == "session@example.com"))
  end

  feature "applies a batch posted from the page and shows its row through the stream, not a reload",
          %{session: session} do
    session = log_in(session)

    mark_this_page_load(session)

    post_batch(session, 1, [create_note_write(session_user().id, "posted")])

    assert await_response(session) == %{"status" => "confirmed", "dropped" => %{}}

    session
    |> assert_text(css("#notes"), "posted")
    |> assert_same_page_load()

    assert [%Note{body: "posted"}] = DB.read(Note)
  end

  feature "refuses a batch the acting user's policies deny", %{session: session} do
    session = log_in(session)

    other_author =
      %{email: "other@example.com"}
      |> User.new()
      |> DB.create!()

    post_batch(session, 1, [create_note_write(other_author.id, "denied")])

    response = await_response(session)

    assert response["status"] == "rejected"
    assert response["write"] == 0
    assert response["reason"] =~ "not allowed to create"

    assert DB.read(Note) == []
  end

  feature "applies a batch that arrives twice once", %{session: session} do
    session = log_in(session)

    writes = [create_note_write(session_user().id, "once")]

    post_batch(session, 1, writes)
    first_response = await_response(session)

    post_batch(session, 1, writes)
    second_response = await_response(session)

    assert first_response == %{"status" => "confirmed", "dropped" => %{}}
    assert second_response == first_response

    assert [%Note{body: "once"}] = DB.read(Note)
  end

  feature "refuses a batch built against another model", %{session: session} do
    session = log_in(session)

    script = """
    globalThis.Hologram.sync.modelHash = "not-this-build";
    """

    execute_script(session, script)

    post_batch(session, 1, [create_note_write(session_user().id, "stale")])

    response = await_response(session)

    assert response["status"] == "rejected"
    assert response["write"] == nil
    assert response["reason"] == ~s[Type.atom("stale_build")]

    assert DB.read(Note) == []
    assert Model.hash() != "not-this-build"
  end

  feature "keeps a batch the acting user's policies deny, with its writes and the reason", %{
    session: session
  } do
    session = log_in(session)
    replica_id = page_replica_id(session)

    other_author =
      %{email: "other@example.com"}
      |> User.new()
      |> DB.create!()

    writes = [create_note_write(other_author.id, "kept")]

    post_batch(session, 1, writes)

    response = await_response(session)

    assert response["status"] == "rejected"

    assert [row] = record_rows(replica_id)
    assert row.actor_id == session_user().id

    # What the browser was told is what the table holds.
    assert row.result == response

    assert row.envelope["replica_id"] == replica_id
    assert row.envelope["seq"] == 1
    assert row.envelope["writes"] == writes

    assert DB.read(Note) == []
  end

  feature "answers a refused batch posted again from its record", %{session: session} do
    session = log_in(session)
    replica_id = page_replica_id(session)
    id = Entity.generate_id()

    post_batch(session, 1, [pin_note_write(id)])

    first = await_response(session)

    assert first["status"] == "rejected"
    assert first["reason"] == ~s[Type.atom("not_found")]

    # The world changes between the two posts: the row the write names now exists, so a second
    # evaluation would answer something else - a denial, since a row created from the test process
    # has no acting user to grant its creator role. An answer that still says :not_found is one
    # the record replayed.
    %{id: id, body: "late", author_id: session_user().id}
    |> Note.new()
    |> DB.create!()

    post_batch(session, 1, [pin_note_write(id)])

    assert await_response(session) == first

    assert [%Note{pinned: false}] = DB.read(Note)
    assert length(record_rows(replica_id)) == 1
  end

  feature "keeps nothing of a batch refused before anyone is logged in", %{session: session} do
    session = visit(session, MutationsPage)
    replica_id = page_replica_id(session)

    author =
      %{email: "nobody@example.com"}
      |> User.new()
      |> DB.create!()

    post_batch(session, 1, [create_note_write(author.id, "anonymous")])

    assert await_response(session)["status"] == "rejected"

    assert record_rows(replica_id) == []
    assert DB.read(Note) == []
  end

  feature "refuses a batch whose identity token was tampered with", %{session: session} do
    session = log_in(session)

    identity = %{
      replica_id: page_replica_id(session),
      replica_token: page_replica_token(session) <> "x"
    }

    post_batch(session, 1, [create_note_write(session_user().id, "tampered")], identity)

    assert await_response(session) == %{"status" => 403}

    assert DB.read(Note) == []
  end

  feature "refuses a batch sent under another replica's identity", %{session: session} do
    session = log_in(session)

    victim_id = Entity.generate_id()

    # Minted from the test process with the framework's own key, bound to a session this browser
    # does not have - what a stranger would hold after learning an id and forging the rest.
    identity = %{
      replica_id: victim_id,
      replica_token: ReplicaIdentity.issue(victim_id, "another-session", nil)
    }

    post_batch(session, 1, [create_note_write(session_user().id, "stolen")], identity)

    assert await_response(session) == %{"status" => 403}

    assert record_rows(victim_id) == []
    assert DB.read(Note) == []
  end

  feature "adds up two increments posted against the same starting value", %{session: session} do
    item = create_item(0)

    session = log_in(session)

    mark_this_page_load(session)

    assert_text(session, css("#items"), "widget: 0")

    post_batch(session, 1, [move_stock_write(item.id, 1)])

    assert await_response(session) == %{"status" => "confirmed", "dropped" => %{}}

    post_batch(session, 2, [move_stock_write(item.id, 1)])

    assert await_response(session) == %{"status" => "confirmed", "dropped" => %{}}

    session
    |> assert_text(css("#items"), "widget: 2")
    |> assert_same_page_load()

    assert [%Item{stock: 2}] = DB.read(Item)
  end

  feature "refuses a decrement that would cross the attribute's minimum", %{session: session} do
    item = create_item(1)

    session = log_in(session)

    post_batch(session, 1, [move_stock_write(item.id, -2)])

    response = await_response(session)

    assert response["status"] == "rejected"
    assert response["write"] == 0

    assert response["reason"] ==
             ~s|Type.map([[Type.atom("stock"), Type.list([Type.tuple([Type.atom("min"), Type.integer(0n)])])]])|

    assert [%Item{stock: 1}] = DB.read(Item)
  end

  feature "moves a counter on the server through a command", %{session: session} do
    create_item(0)

    session = log_in(session)

    mark_this_page_load(session)

    session
    |> click(button("Restock item"))
    |> assert_text(css("#result"), "restocked_item")
    |> assert_text(css("#items"), "widget: 1")
    |> assert_same_page_load()

    assert [%Item{stock: 1}] = DB.read(Item)
  end

  feature "runs a job created by a batch once the batch commits", %{session: session} do
    item = create_item(0)

    session = log_in(session)

    mark_this_page_load(session)

    assert_text(session, css("#items"), "widget: 0")

    post_batch(session, 1, [create_restock_write(item.id, 1)])

    assert await_response(session) == %{"status" => "confirmed", "dropped" => %{}}

    session
    |> assert_text(css("#items"), "widget: 1")
    |> assert_text(css("#jobs"), "1:done")
    |> assert_same_page_load()

    assert [%RestockItem{status: :done, error: nil, actor_id: actor_id}] = DB.read(RestockItem)
    assert actor_id == session_user().id
  end

  feature "creates no job when the batch it rode in is refused", %{session: session} do
    item = create_item(0)

    session = log_in(session)

    other_author =
      %{email: "other@example.com"}
      |> User.new()
      |> DB.create!()

    writes = [create_restock_write(item.id, 1), create_note_write(other_author.id, "denied")]

    post_batch(session, 1, writes)

    assert await_response(session)["status"] == "rejected"

    assert DB.read(RestockItem) == []
    assert [%Item{stock: 0}] = DB.read(Item)
  end

  feature "records a job that fails, with the error on its own row", %{session: session} do
    item = create_item(0)

    session = log_in(session)

    # Moving the stock below the item's declared minimum is refused by the write, and the refusal
    # raises out of the job's run/1.
    post_batch(session, 1, [create_restock_write(item.id, -5)])

    assert await_response(session) == %{"status" => "confirmed", "dropped" => %{}}

    assert_text(session, css("#jobs"), "-5:failed")

    assert [%RestockItem{status: :failed, error: error}] = DB.read(RestockItem)
    assert error =~ "cannot update"
    assert [%Item{stock: 0}] = DB.read(Item)
  end

  feature "runs a job created by a command, as the session's user", %{session: session} do
    create_item(0)

    session = log_in(session)

    mark_this_page_load(session)

    session
    |> click(button("Create restock job"))
    |> assert_text(css("#result"), "created_restock_job")
    |> assert_text(css("#items"), "widget: 1")
    |> assert_text(css("#jobs"), "1:done")
    |> assert_same_page_load()

    assert [%RestockItem{status: :done, actor_id: actor_id}] = DB.read(RestockItem)
    assert actor_id == session_user().id
  end
end
