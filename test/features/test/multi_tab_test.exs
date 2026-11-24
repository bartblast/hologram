defmodule HologramFeatureTests.MultiTabTest do
  # async: false - each test truncates the shared table, and one the operations log.
  use HologramFeatureTests.TestCase, async: false

  alias Hologram.DB
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias HologramFeatureTests.ActionWritesPage
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
    table = ~s("hologram_data"."#{Mapper.table_name(Todo)}")

    {:ok, _result} = Connection.query("TRUNCATE #{table}", [])

    :ok
  end

  defp leader?(session) do
    script_result(session, "return globalThis.Hologram.durability.leader();")
  end

  # What a tab that files a batch and closes, or runs late, looks like to the others: the batch is
  # in the store and nobody hears of it.
  defp drop_sealed_messages(session) do
    execute_script(session, """
    const post = BroadcastChannel.prototype.postMessage;

    BroadcastChannel.prototype.postMessage = function (message) {
      if (message?.kind !== "sealed") {
        post.call(this, message);
      }
    };
    """)
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

  # How long a page bundle the browser has not fetched yet is held, which is how long a tab opened
  # on such a page is starting up: joined, with the store read, and not mounted.
  @bundle_hold_ms 6_000

  # A starting tab that leads its group, behind the one the test is on - which goes to a blank page
  # first, where the slow bundle is armed, and so leaves the group to the starting tab. Answers the
  # starting tab's handle and when it was opened.
  defp open_starting_leader(session) do
    session =
      session
      |> simulate_slow_page_bundle(@bundle_hold_ms)
      |> await_leader_locks(:held, 0)

    opened_at = System.monotonic_time(:millisecond)
    handle = open_tab_behind(session, ActionWritesPage)

    await_leader_locks(session, :held, 1)

    {handle, opened_at}
  end

  # What a test proves happened while a tab was starting, it proves only if the tab was: mounted
  # already, the tab behaves as it should with or without the fix.
  defp assert_still_starting(opened_at) do
    assert System.monotonic_time(:millisecond) - opened_at < @bundle_hold_ms
  end

  defp await_server_todo_title(title, attempts_left \\ 100)

  defp await_server_todo_title(_title, 0), do: false

  defp await_server_todo_title(title, attempts_left) do
    todos = DB.read(Todo)

    if Enum.any?(todos, &(&1.title == title)) do
      true
    else
      Process.sleep(50)
      await_server_todo_title(title, attempts_left - 1)
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

  # The tab whose write failed goes on with no store, and the tab that leads keeps it. Counting under
  # the identity they shared, both would take the same next number, and the server would answer one
  # write from the record of the other.
  feature "lands the writes of each tab after one tab's store write fails", %{session: session} do
    leading =
      session
      |> visit(WriteQueuePage)
      |> click(button("Create alpha"))

    first = tab_handle(leading)
    replica = replica_id(leading)

    assert [%Todo{title: "alpha"}] = await_server_todos(1)

    following =
      leading
      |> await_pending_writes(0)
      |> open_tab(WriteQueuePage)

    refute leader?(following)
    assert replica_id(following) == replica

    failing =
      following
      |> fail_store_writes()
      |> click(button("Create gamma"))
      |> await_memory_mode()
      |> assert_text(css("#todos"), "gamma 0")

    failing_tab = tab_handle(failing)

    assert length(await_server_todos(2)) == 2

    # Closed once the tab holds an identity of its own, so it's numbered under it from the start.
    failing
    |> await_pending_writes(0)
    |> click(button("Create gamma"))

    assert length(await_server_todos(3)) == 3

    failing
    |> await_pending_writes(0)
    |> focus_tab(first)
    |> click(button("Rename alpha"))
    |> assert_text(css("#todos"), "beta 0")

    assert await_server_todo_title("beta")

    leading_replica = replica_id(failing)

    focus_tab(failing, failing_tab)

    refute leading_replica == replica_id(failing)
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
  #
  # The send is HELD, and not for convenience: a duplicate slug is refused in milliseconds, so
  # asserting the row is on screen without holding races the round trip - and lost that race on CI,
  # where the server answered before the driver could look. Holding makes the optimistic row a
  # state the test can stand in, and every claim after the release is anchored on the refusal
  # arriving rather than on a moment.
  feature "rolls a refused write back in the tab that made it", %{session: session} do
    %{slug: "taken", title: "taken"}
    |> Todo.new()
    |> DB.create!()

    sender =
      session
      |> visit(WriteQueuePage)
      |> hold_mutation_requests()

    first = tab_handle(sender)

    writer =
      sender
      |> open_tab(WriteQueuePage)
      |> assert_text(css("#todos"), "taken 0")
      |> click(button("Create a duplicate slug"))
      |> assert_text(css("#todos"), "dup 0")

    second = tab_handle(writer)

    # On screen in the tab that did not make it, and still unsent - the gate lives in this tab,
    # which is why the release happens here.
    releasing =
      writer
      |> focus_tab(first)
      |> assert_text(css("#todos"), "dup 0")

    release_mutations(releasing)

    assert [%{"seq" => 1, "write" => 0}] = await_rejected_writes(releasing)

    refute_text(releasing, css("#todos"), "dup")

    # And the tab that MADE the write learns a verdict it never asked for.
    author = focus_tab(releasing, second)

    assert [%{"seq" => 1, "write" => 0}] = await_rejected_writes(author)

    refute_text(author, css("#todos"), "dup")

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

  # The later batch is announced and the earlier one isn't, so a sender that followed the
  # announcements alone would go past the earlier one and never send it.
  #
  # The heartbeat is set far apart so that no beat wakes the sender between the two writes.
  feature "sends a write nobody announced when a later one is announced", %{session: session} do
    # A stream opening wakes the sender too, so the fill it delivers has to land before the first
    # write.
    session
    |> simulate_fast_sse_heartbeat(60_000)
    |> visit(WriteQueuePage)
    |> await_leader()
    |> await_local_fill()
    |> open_tab(WriteQueuePage)
    |> drop_sealed_messages()
    |> click(button("Create alpha"))
    |> assert_text(css("#todos"), "alpha 0")
    |> await_durable_writes()
    |> open_tab(WriteQueuePage)
    |> click(button("Create gamma"))

    assert [%Todo{title: "alpha"}, %Todo{title: "gamma"}] = await_server_todos(2)
  end

  # Nobody acts after the write and the stream is already open, so its heartbeat is the only thing
  # left to wake the sender. A second apart, so a slow machine doesn't miss two beats, which would
  # reopen the stream, and that wakes the sender too.
  feature "sends a write nobody announced with no other tab acting", %{session: session} do
    session
    |> simulate_fast_sse_heartbeat(1_000)
    |> visit(WriteQueuePage)
    |> await_leader()
    |> await_local_fill()
    |> open_tab(WriteQueuePage)
    |> drop_sealed_messages()
    |> click(button("Create alpha"))

    assert [%Todo{title: "alpha"}] = await_server_todos(1)
  end

  # A starting tab learns what the group holds two ways: from the store it reads, and from the
  # frames the leading tab posts once it is listening. A frame stored after its read and posted
  # before it listened would reach it neither way, so it joins the group before it reads.
  #
  # The store block holds the second tab's read, and the leading tab's write of the frame behind
  # it, for as long as the test wants - so the frame is certainly stored after the read. The second
  # tab's page is rendered before the row exists, so no row the page carried hides a miss.
  feature "shows a row sent while a new tab was reading the store", %{session: session} do
    leading =
      session
      |> visit(WriteQueuePage)
      |> await_local_fill()

    first = tab_handle(leading)

    starting =
      leading
      |> block_store()
      |> open_tab_unmounted(WriteQueuePage)

    second = tab_handle(starting)

    # Its read of the store is under way, and held, before the row exists.
    starting
    |> focus_tab(first)
    |> await_store_read_waiting()

    %{title: "alpha"}
    |> Todo.new()
    |> DB.create!()

    starting
    |> assert_text(css("#todos"), "alpha 0")
    |> unblock_store()
    |> focus_tab(second)
    |> await_page_mount(WriteQueuePage)
    |> assert_text(css("#todos"), "alpha 0")
  end

  # The same gap in the middle of a fill, where it also decides what a tab is told is complete. The
  # leading tab is filled again with every frame of the fill held, the second tab starts and its
  # read of the emptied store is blocked, and then the fill is let through: its rows and its marker
  # are stored after that read. A tab that missed them would still hear the group's state, which
  # says everything is complete, and would sweep the row its own page carried.
  #
  # Emptying the operations log is the lever for the refill, as in the resync tests.
  feature "holds every row of a fill it started in the middle of", %{session: session} do
    %{title: "alpha"}
    |> Todo.new()
    |> DB.create!()

    leading =
      session
      |> visit(WriteQueuePage)
      |> await_local_fill()
      |> hold_sync_frames()

    truncate_oplog()
    simulate_sse_disconnect(current_instance_id(leading))

    # The fill is under way and held, and the start-over before it, which is not held, emptied the
    # store.
    first =
      leading
      |> await_held_sync_frame()
      |> assert_no_place()
      |> tab_handle()

    starting =
      leading
      |> block_store()
      |> open_tab_unmounted(WriteQueuePage)

    second = tab_handle(starting)

    starting
    |> focus_tab(first)
    |> await_store_read_waiting()
    |> release_sync_frames()
    |> await_local_fill()
    |> unblock_store()
    |> focus_tab(second)
    |> await_page_mount(WriteQueuePage)
    |> await_local_fill()
    |> assert_text(css("#todos"), "alpha 0")

    %{title: "beta"}
    |> Todo.new()
    |> DB.create!()

    # Beta first: a render that shows it comes after any sweep of the row the page carried.
    starting
    |> assert_text(css("#todos"), "beta 0")
    |> assert_text(css("#todos"), "alpha 0")
  end

  # A tab that leads says what it holds only once it holds it. Before its mount it holds its page's
  # identity, not the one the browser stored - and a tab that joined meanwhile would take that one
  # from it and number its writes under an identity nothing in the store knows.
  feature "keeps the stored identity while the leading tab is still starting", %{session: session} do
    stored =
      session
      |> visit(WriteQueuePage)
      |> await_durable_writes()
      |> replica_id()

    {_handle, opened_at} = open_starting_leader(session)

    following = open_tab(session, WriteQueuePage)

    refute leader?(following)

    # Time for an answer to its request for the group's state, which the starting tab holds.
    Process.sleep(500)

    assert replica_id(following) == stored
    assert_still_starting(opened_at)
  end

  # A batch another tab files wakes the tab that leads - which, still starting, has not taken up the
  # identity the stored queue was numbered under, and would send it under its page's own. The
  # server would then apply it again on the next page load that sends it under the right one.
  feature "sends a stored write under the identity it was numbered under", %{session: session} do
    writer =
      session
      |> visit(WriteQueuePage)
      |> hold_mutation_requests()
      |> click(button("Create alpha"))
      |> await_pending_writes(1)
      |> await_durable_writes()

    stored = replica_id(writer)

    {leading, opened_at} = open_starting_leader(writer)

    following = open_tab(writer, WriteQueuePage)

    refute leader?(following)

    following
    |> click(button("Create gamma"))
    |> await_durable_writes()

    assert_still_starting(opened_at)

    following
    |> focus_tab(leading)
    |> await_page_mount(ActionWritesPage)

    assert [%Todo{title: "alpha"}, %Todo{title: "gamma"}] = await_server_todos(2)

    assert [%{seq: 1}, %{seq: 2}] = mutation_record_rows(stored)
  end

  # A batch is taken up only by a page mounted under the user who made it, and a starting tab is
  # mounted under nobody yet - so one taken up before the mount would be passed over, and nothing
  # would bring it back. Held until the tab has mounted, it is taken up under the user signed in.
  #
  # The write is held at the tab that sends, so nothing but the filed batch can show it. And it is
  # filed after the starting tab's read of the store: the store block holds that read, and the
  # write queues behind it, so the read cannot find the batch there.
  feature "shows a write another tab made while this one was starting", %{session: session} do
    # The slow bundle is armed on a blank page, so the tab comes back to its page afterwards -
    # mounted under Alice now, and with a bundle the browser has, so at once.
    writer =
      session
      |> visit(WriteQueuePage)
      |> click(button("Log in as Alice"))
      |> assert_text(css("#result"), "logged_in_alice")
      |> simulate_slow_page_bundle(@bundle_hold_ms)
      |> visit(WriteQueuePage)
      |> await_page_mount(WriteQueuePage)
      |> hold_mutation_requests()

    # Signed in: an anonymous page takes up every batch whenever it does.
    group = script_result(writer, "return globalThis.Hologram.durability.group();")

    refute String.ends_with?(group, ".anonymous")

    opened_at = System.monotonic_time(:millisecond)
    second = open_tab_behind(block_store(writer), ActionWritesPage)

    writer
    |> await_store_read_waiting()
    |> click(button("Create alpha"))
    |> assert_text(css("#todos"), "alpha 0")
    |> unblock_store()
    |> await_durable_writes()

    assert_still_starting(opened_at)

    writer
    |> focus_tab(second)
    |> await_page_mount(ActionWritesPage)
    |> assert_text(css("#todos"), "alpha 0")

    assert DB.read(Todo) == []
  end
end
