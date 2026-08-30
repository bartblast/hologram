defmodule HologramFeatureTests.ResyncTest do
  # async: false - each test truncates the shared table and the operations log.
  use HologramFeatureTests.TestCase, async: false

  import Hologram.DB.EntityOperations, only: [delete: 2]

  alias Hologram.DB
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias HologramFeatureTests.ActionWritesPage
  alias HologramFeatureTests.Entities.Todo

  # What a browser does between being told to start over and being sent everything again. It keeps
  # what it holds, on screen and readable, and the marker ending the refill takes away whatever the
  # refill did not bring back.
  #
  # The lever is the operations log: emptying it leaves a returning client naming a place the log
  # cannot speak for, which is answered `:retention` - the same "start over" a client away past the
  # log's reach gets, provoked without waiting for one. The client reconnects on its own after the
  # stream is killed, so nothing here fights `visit/3`'s connection barrier.
  #
  # Order matters: empty the log FIRST, then make the server-side change, so that change is the
  # newest thing in a log the client's place still predates.

  setup do
    await_evaluator_drain()

    table = ~s("hologram_data"."#{Mapper.table_name(Todo)}")

    {:ok, _result} = Connection.query("TRUNCATE #{table}", [])

    :ok
  end

  # Polls until the client holds a place again, which is what the marker ending a refill hands it -
  # so this is how a test waits for a whole fill to have finished.
  defp await_place(session, attempts_left \\ 100)

  defp await_place(session, 0), do: session

  defp await_place(session, attempts_left) do
    if script_result(session, "return globalThis.Hologram.durability.cursor();") do
      session
    else
      Process.sleep(50)
      await_place(session, attempts_left - 1)
    end
  end

  # The mirror: a client told to start over gives up its place with the rows it described, so this
  # is how a test waits for the "start over" frame to have been processed.
  defp await_no_place(session, attempts_left \\ 100)

  defp await_no_place(session, 0), do: session

  defp await_no_place(session, attempts_left) do
    if script_result(session, "return globalThis.Hologram.durability.cursor();") do
      Process.sleep(50)
      await_no_place(session, attempts_left - 1)
    else
      session
    end
  end

  defp assert_no_place(session) do
    assert_script_result(session, "return globalThis.Hologram.durability.cursor();", nil)
  end

  # Proves the DOM changed without the page being fetched again: a reload would take this marker
  # with it, so a passing assertion after one would say nothing.
  defp mark_this_page_load(session) do
    execute_script(session, "globalThis.__thisPageLoad = 'held';")
  end

  defp assert_same_page_load(session) do
    assert_script_result(session, "return globalThis.__thisPageLoad;", "held")
  end

  defp truncate_outbox do
    {:ok, _result} = Connection.query(~s(TRUNCATE "hologram_system"."outbox"), [])

    :ok
  end

  # The feature this issue exists for, and it FAILS against the framework as it was before it: an
  # emptied database answers the action's read with nothing, the action raises before it can set
  # the result, and the row it raised over is on the screen the whole time.
  feature "keeps a row on screen usable while the refill is arriving", %{session: session} do
    %{title: "alpha"}
    |> Todo.new()
    |> DB.create!()

    session =
      session
      |> visit(ActionWritesPage)
      |> assert_text(css("#todos"), "alpha 0")
      |> await_place()
      |> mark_this_page_load()
      |> hold_sync_frames()

    truncate_outbox()
    simulate_sse_disconnect(current_instance_id(session))

    session
    |> await_no_place()
    |> click(button("Vote"))
    |> assert_text(css("#result"), "voted_1")
    |> assert_text(css("#todos"), "alpha 1")
    # The hold is what puts the click inside the window, and a hold that silently stopped working -
    # the stream being built somewhere other than the connect would do it - leaves the assertions
    # above passing for the ordinary reason instead. Still holding no place says the refill really
    # had not landed when they were made.
    |> assert_no_place()
    |> assert_same_page_load()
    |> release_sync_frames()
    |> await_place()
    |> assert_text(css("#todos"), ~r/^alpha 1$/)

    assert [%Todo{title: "alpha", votes: 1}] = await_server_todos(1)
  end

  # The other half, end to end in a browser: what the refill does not bring back goes. This one
  # passes against the pre-fix framework too - an emptied database also ends up showing only what
  # the refill delivered - and it is here because the sweep is what makes keeping the rows safe.
  feature "takes a row the refill did not bring back off at the end", %{session: session} do
    %{title: "alpha"}
    |> Todo.new()
    |> DB.create!()

    beta =
      %{title: "beta"}
      |> Todo.new()
      |> DB.create!()

    session =
      session
      |> visit(ActionWritesPage)
      |> assert_text(css("#todos"), "alpha 0")
      |> assert_text(css("#todos"), "beta 0")
      |> await_place()
      |> mark_this_page_load()

    truncate_outbox()
    :ok = delete(Todo, beta.id)

    simulate_sse_disconnect(current_instance_id(session))

    session
    |> assert_text(css("#todos"), ~r/^alpha 0$/)
    |> assert_same_page_load()
  end
end
