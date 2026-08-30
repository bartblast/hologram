defmodule HologramFeatureTests.WriteQueueTest do
  # async: false - each test truncates the shared table.
  use HologramFeatureTests.TestCase, async: false

  alias Hologram.DB
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias HologramFeatureTests.Entities.Todo
  alias HologramFeatureTests.WriteQueuePage

  # What the browser does with a write it could not deliver, across a page load. The lever in
  # every scenario is `hold_mutation_requests/1`: it parks the batch's request on the page that
  # made it, and a reload takes that page - and the parked request - with it. Whatever reaches the
  # server afterwards was taken up by the NEXT page load, out of the browser's own store.
  #
  # Todo references nothing, so it truncates alone. User is deliberately NOT truncated: it is
  # referenced by other tables, and the sign-in commands find their user by email, so one left by
  # an earlier run is exactly the row they want.
  setup do
    await_evaluator_drain()

    table = ~s("hologram_data"."#{Mapper.table_name(Todo)}")

    {:ok, _result} = Connection.query("TRUNCATE #{table}", [])

    :ok
  end

  defp replica_id(session) do
    script_result(session, "return globalThis.Hologram.durability.replicaId();")
  end

  defp stored_batches(session) do
    script_result(session, "return globalThis.Hologram.durability.storedBatches();")
  end

  # A batch is applied by the server under the user of the session that SENDS it, so a page
  # somebody else has signed in on must not send it - and must not drop it either. The negative
  # half (Bob's page sends nothing) is pinned by the positive halves around it: the batch is still
  # STORED while Bob is signed in, and it LANDS once Alice is back. A run in which Bob's page sent
  # it fails `DB.read(Todo) == []`, and a run in which it was dropped fails the final
  # `await_server_todos(1)`.
  #
  # Each sign-in is followed by a reload, because a command changes the session and not the page
  # already mounted - the owner a page's batches are sealed under is the one it was MOUNTED under.
  feature "keeps a write made by another user waiting for that user", %{session: session} do
    session
    |> visit(WriteQueuePage)
    |> click(button("Log in as Alice"))
    |> assert_text(css("#result"), "logged_in_alice")
    |> reload()
    |> assert_page(WriteQueuePage)
    |> hold_mutation_requests()
    |> click(button("Create alpha"))
    |> assert_text(css("#todos"), "alpha 0")
    |> await_pending_writes(1)
    |> await_durable_writes()
    |> click(button("Log in as Bob"))
    |> assert_text(css("#result"), "logged_in_bob")
    |> reload()
    |> assert_page(WriteQueuePage)
    |> await_pending_writes(0)

    assert stored_batches(session) == 1

    refute_text(session, css("#todos"), "alpha")

    assert DB.read(Todo) == []

    session
    |> click(button("Log in as Alice"))
    |> assert_text(css("#result"), "logged_in_alice")
    |> reload()
    |> assert_page(WriteQueuePage)
    |> assert_text(css("#todos"), "alpha 0")

    assert [%Todo{title: "alpha"}] = await_server_todos(1)
  end

  # A refusal that lands on a page that did not make the write. Uniqueness is a question about rows
  # the client does not hold, so the create passes in the browser, is stored, and is refused only
  # when the NEXT page load sends it - and that page has to roll back a row it restored from the
  # store rather than one an action of its own put there.
  feature "rolls back a write refused after a reload", %{session: session} do
    %{slug: "taken", title: "taken"}
    |> Todo.new()
    |> DB.create!()

    session =
      session
      |> visit(WriteQueuePage)
      |> assert_text(css("#todos"), "taken 0")
      |> hold_mutation_requests()
      |> click(button("Create a duplicate slug"))
      |> assert_text(css("#todos"), "dup 0")
      |> await_pending_writes(1)
      |> await_durable_writes()
      |> reload()
      |> assert_page(WriteQueuePage)

    assert [%{"seq" => 1, "write" => 0}] = await_rejected_writes(session)

    refute_text(session, css("#todos"), "dup")

    assert [%Todo{title: "taken"}] = DB.read(Todo)

    assert [%{seq: 1, result: %{"status" => "rejected"}}] =
             mutation_record_rows(replica_id(session))
  end

  # The whole point of the queue, in one round trip: the write outlives the page that made it, is
  # on screen again before anything is sent, and reaches the server under the identity the browser
  # KEPT - which is what lets the server's record of it stay in one place.
  feature "sends a write the previous page load could not", %{session: session} do
    session =
      session
      |> visit(WriteQueuePage)
      |> hold_mutation_requests()
      |> click(button("Create alpha"))
      |> assert_text(css("#todos"), "alpha 0")
      |> await_pending_writes(1)
      |> await_durable_writes()

    held = replica_id(session)

    session
    |> reload()
    |> assert_page(WriteQueuePage)
    |> assert_text(css("#todos"), "alpha 0")

    assert [%Todo{title: "alpha", votes: 0}] = await_server_todos(1)

    session
    |> await_pending_writes(0)
    |> assert_script_result("return globalThis.Hologram.writes.pendingCount();", 0)

    assert [%{seq: 1, result: %{"status" => "confirmed"}}] = mutation_record_rows(held)
  end

  # The second batch names the row the first one created, so the order is load-bearing: were the
  # rename sent first it would be refused for naming a row the server does not hold, and the
  # server would end up with `alpha`. The record's two confirmed numbers are what pin it.
  feature "sends the writes in the order they were made", %{session: session} do
    session =
      session
      |> visit(WriteQueuePage)
      |> hold_mutation_requests()
      |> click(button("Create alpha"))
      |> assert_text(css("#todos"), "alpha 0")
      |> click(button("Rename alpha"))
      |> assert_text(css("#todos"), "beta 0")
      |> await_pending_writes(2)
      |> await_durable_writes()
      |> reload()
      |> assert_page(WriteQueuePage)

    assert [%Todo{title: "beta"}] = await_server_todos(1)

    assert [
             %{seq: 1, result: %{"status" => "confirmed"}},
             %{seq: 2, result: %{"status" => "confirmed"}}
           ] = mutation_record_rows(replica_id(session))
  end
end
