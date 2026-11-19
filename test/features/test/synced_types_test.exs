defmodule HologramFeatureTests.SyncedTypesTest do
  # async: false - each test truncates shared tables, and one the operations log.
  use HologramFeatureTests.TestCase, async: false

  alias Hologram.DB
  alias HologramFeatureTests.Entities.Bookmark
  alias HologramFeatureTests.Entities.Todo
  alias HologramFeatureTests.SyncedTypesCountPage
  alias HologramFeatureTests.SyncedTypesPage

  setup do
    await_evaluator_drain()
    truncate_entity_tables([Bookmark, Todo])
  end

  # A count on a page the stream was not greeted with goes local as soon as the type it counts is
  # complete, rather than once everything is. The client is sent everything again with the marker
  # saying everything is complete held back, then navigates: the count shows the todo it just wrote
  # only if it counts its own rows. Before, a page reached after the first waited for that marker
  # and showed the number the server rendered.
  #
  # Emptying the operations log is the lever for the refill, as in the resync tests: the client's
  # place is one the log can no longer speak for, so it is told to start over.
  feature "counts on a page reached after the first once the type it counts is complete",
          %{session: session} do
    %{title: "alpha"}
    |> Todo.new()
    |> DB.create!()

    session =
      session
      |> visit(SyncedTypesPage)
      |> await_local_fill()
      |> mark_this_page_load()
      |> hold_sync_frames(only: :all)

    truncate_oplog()
    simulate_sse_disconnect(current_instance_id(session))

    session
    |> await_held_sync_frame()
    # Holding no place says the client really was told to start over and is still waiting for
    # everything - a resumed client is sent the same last marker, and still holds the first fill's.
    |> assert_no_place()
    |> click(link("Count link"))
    |> assert_page(SyncedTypesCountPage)
    |> assert_text(css("#todo_count"), "1")
    |> click(button("Add a todo"))
    |> assert_text(css("#todo_count"), "2")
    |> assert_no_place()
    |> assert_same_page_load()

    # The write settles before the next test empties the table it lands in.
    assert [_alpha, _added] = await_server_todos(2)
  end

  # No window reads bookmarks, so before, a change to one never reached a browser that already held
  # it: what a client is told live goes by what its user may read.
  feature "changes live a row of a type only an action reads", %{session: session} do
    bookmark =
      %{label: "draft"}
      |> Bookmark.new()
      |> DB.create!()

    session =
      session
      |> visit(SyncedTypesPage)
      |> await_local_fill()
      |> mark_this_page_load()
      |> await_local_read("Read the labels", "labels", "draft")

    DB.update!(Bookmark, bookmark.id, label: "pinned")

    session
    |> await_local_read("Read the labels", "labels", "pinned")
    |> assert_same_page_load()
  end

  # No query on any page reads bookmarks, only an action does - so before, no row of one ever
  # reached the browser, and the action found nothing.
  feature "fills a type only an action reads", %{session: session} do
    %{label: "pinned"}
    |> Bookmark.new()
    |> DB.create!()

    session
    |> visit(SyncedTypesPage)
    |> await_local_fill()
    |> click(button("Read the bookmark"))
    |> assert_text(css("#result"), "found_pinned")
  end
end
