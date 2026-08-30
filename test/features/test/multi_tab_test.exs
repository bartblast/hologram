defmodule HologramFeatureTests.MultiTabTest do
  # async: false - each test truncates the shared table.
  use HologramFeatureTests.TestCase, async: false

  alias Hologram.DB
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias HologramFeatureTests.Entities.Todo
  alias HologramFeatureTests.WriteQueuePage

  # What two tabs of one browser do, which is the whole of this issue: they share the stored rows,
  # the queue of writes waiting to go out and the identity those writes are numbered under - and
  # one of them, elected by a lock the browser hands out, holds the sync stream and sends for the
  # rest.
  #
  # A second Wallaby SESSION would be a second browser, with its own profile and its own storage,
  # and could say nothing about any of that. So every scenario here opens a second TAB
  # (`open_tab/3`) and moves between them by handle.
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

  defp leader?(session) do
    script_result(session, "return globalThis.Hologram.durability.leader();")
  end

  # A tab takes the lead when the browser grants it the lock the tab before it was holding, which
  # happens whenever that tab goes - so this is polled rather than read.
  defp await_leader(session, attempts_left \\ 100)

  defp await_leader(session, 0) do
    raise Wallaby.ExpectationNotMetError,
          "Timed out waiting for the tab to take the lead, it reads #{inspect(leader?(session))}"
  end

  defp await_leader(session, attempts_left) do
    if leader?(session) do
      session
    else
      Process.sleep(50)
      await_leader(session, attempts_left - 1)
    end
  end

  defp replica_id(session) do
    script_result(session, "return globalThis.Hologram.durability.replicaId();")
  end

  # One session for the browser rather than one per tab, which is what the second tab costing the
  # server nothing looks like from the outside. The replica is what scopes it: the number is what
  # THIS browser costs, and the tabs share one identity because they share one store.
  feature "runs one sync session for two tabs", %{session: session} do
    leading = visit(session, WriteQueuePage)

    first = tab_handle(leading)
    replica = replica_id(leading)

    assert leader?(leading)

    following = open_tab(leading, WriteQueuePage)

    refute leader?(following)
    assert replica_id(following) == replica

    assert await_sync_sessions(replica, 1) == 1

    assert leader?(focus_tab(following, first))
  end

  # The tab that follows has no sync session of its own, so a row it shows can only have reached it
  # through the tab that has one - which is the fan-out, observed from the outside.
  feature "shows a row the server created in both tabs", %{session: session} do
    leading = visit(session, WriteQueuePage)
    first = tab_handle(leading)
    following = open_tab(leading, WriteQueuePage)

    %{title: "alpha"}
    |> Todo.new()
    |> DB.create!()

    following
    |> assert_text(css("#todos"), "alpha 0")
    |> focus_tab(first)
    |> assert_text(css("#todos"), "alpha 0")
  end

  # The write is made in the tab that does NOT send, and the server has not heard of it while the
  # assertions run - so what either tab shows came out of the browser rather than out of a frame.
  # Held in the first tab because that is the one that sends: the gate wraps the fetch of whichever
  # tab it was installed in.
  feature "shows a write made in the other tab before the server has it", %{session: session} do
    sender =
      session
      |> visit(WriteQueuePage)
      |> hold_mutation_requests()

    first = tab_handle(sender)

    writer =
      sender
      |> open_tab(WriteQueuePage)
      |> click(button("Create alpha"))
      |> assert_text(css("#todos"), "alpha 0")

    assert DB.read(Todo) == []

    writer
    |> focus_tab(first)
    |> assert_text(css("#todos"), "alpha 0")
    |> release_mutations()

    assert [%Todo{title: "alpha"}] = await_server_todos(1)
  end

  # One counter for the browser, moved where the batch is filed - so two tabs writing at once take
  # two numbers rather than one. The record is what says so: two rows under ONE replica, numbered
  # apart, both confirmed.
  feature "numbers writes made in two tabs apart", %{session: session} do
    leading = visit(session, WriteQueuePage)

    replica = replica_id(leading)

    following =
      leading
      |> click(button("Create alpha"))
      |> open_tab(WriteQueuePage)
      |> click(button("Create gamma"))

    assert [%Todo{title: "alpha"}, %Todo{title: "gamma"}] = await_server_todos(2)

    await_pending_writes(following, 0)

    assert [
             %{seq: 1, result: %{"status" => "confirmed"}},
             %{seq: 2, result: %{"status" => "confirmed"}}
           ] = mutation_record_rows(replica)
  end

  # The write is made in the tab that does not send, refused at the server, and rolled back in BOTH
  # tabs - the tab that made it hears the verdict from the tab that asked for it.
  feature "rolls a refused write back in the tab that made it", %{session: session} do
    %{slug: "taken", title: "taken"}
    |> Todo.new()
    |> DB.create!()

    leading = visit(session, WriteQueuePage)
    first = tab_handle(leading)

    writer =
      leading
      |> open_tab(WriteQueuePage)
      |> assert_text(css("#todos"), "taken 0")
      |> click(button("Create a duplicate slug"))
      |> assert_text(css("#todos"), "dup 0")

    assert [%{"seq" => 1, "write" => 0}] = await_rejected_writes(writer)

    refute_text(writer, css("#todos"), "dup")

    writer
    |> focus_tab(first)
    |> refute_text(css("#todos"), "dup")

    assert [%Todo{title: "taken"}] = DB.read(Todo)
  end

  # Nothing is handed over when a tab goes - the browser grants the lock to whoever has waited
  # longest, and everything the new leader needs is in its own memory or in the store. A row created
  # afterwards is what proves it has a stream: it had none while it followed.
  feature "hands the session to another tab when the leading one closes", %{session: session} do
    leading = visit(session, WriteQueuePage)

    first = tab_handle(leading)
    replica = replica_id(leading)

    following = open_tab(leading, WriteQueuePage)
    second = tab_handle(following)

    survivor =
      following
      |> focus_tab(first)
      |> close_tab(second)
      |> await_leader()

    assert await_sync_sessions(replica, 1) == 1

    %{title: "alpha"}
    |> Todo.new()
    |> DB.create!()

    assert_text(survivor, css("#todos"), "alpha 0")
  end

  # The write outlives the tab that made it, because the tab that sends is not the tab that wrote:
  # it was filed in the queue they share and taken up from there.
  feature "sends a write made in a tab that has closed", %{session: session} do
    sender =
      session
      |> visit(WriteQueuePage)
      |> hold_mutation_requests()

    first = tab_handle(sender)

    writer =
      sender
      |> open_tab(WriteQueuePage)
      |> click(button("Create alpha"))
      |> assert_text(css("#todos"), "alpha 0")
      |> await_pending_writes(1)
      |> await_durable_writes()

    writer
    |> close_tab(first)
    |> release_mutations()

    assert [%Todo{title: "alpha"}] = await_server_todos(1)
  end
end
