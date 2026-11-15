defmodule HologramFeatureTests.StoppedTabTest do
  # async: false - each test truncates the shared table.
  use HologramFeatureTests.TestCase, async: false

  alias Hologram.DB
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias HologramFeatureTests.Entities.Todo
  alias HologramFeatureTests.StoppedTabPage
  alias HologramFeatureTests.WriteQueuePage

  # What a tab does once the server stops serving it after a deploy: it says so, holds the writes
  # the server would refuse, and leaves for its next page by loading it afresh - and never reloads
  # on its own.
  #
  # The tab is made stale by hand: its model hash changed, which is what a bundle from before a
  # deploy that changed the model looks like. The server then stops it when its stream connects
  # again, or when a write reaches the server first. The local database keeps the name the page
  # opened it under, so a reload here finds the held writes and sends them; after a real deploy the
  # new bundle opens another model's database and they stay in the old one.
  setup do
    await_evaluator_drain()

    table = ~s("hologram_data"."#{Mapper.table_name(Todo)}")

    {:ok, _result} = Connection.query("TRUNCATE #{table}", [])

    :ok
  end

  @notice_text "This page was updated and needs a reload to keep your data in sync."

  # Matched by its text, which is written a moment after the card goes up - so a passing match is
  # the notice as the person reads it.
  defp notice, do: css("#hologram-reload-notice", text: @notice_text)

  defp make_stale(session, field \\ "modelHash", value \\ "'not-this-build'") do
    execute_script(session, "globalThis.Hologram.sync.#{field} = #{value};")
  end

  # A stream connecting again greets the server with what the bundle was built against.
  defp stop(session) do
    session = make_stale(session)

    simulate_sse_disconnect(current_instance_id(session))

    assert_has(session, notice())
  end

  # Counts the writes this tab sends, from here on.
  defp count_mutation_requests(session) do
    execute_script(session, """
    const send = window.fetch;
    globalThis.__mutationRequests = 0;

    window.fetch = (resource, ...rest) => {
      if (String(resource).includes("/hologram/mutation")) {
        globalThis.__mutationRequests += 1;
      }

      return send(resource, ...rest);
    };
    """)
  end

  defp assert_mutation_requests(session, count) do
    assert_script_result(session, "return globalThis.__mutationRequests;", count)
  end

  feature "shows a notice in a tab the server stopped serving", %{session: session} do
    session
    |> visit(StoppedTabPage)
    |> mark_this_page_load()
    |> stop()
    |> assert_same_page_load()
  end

  # What the person writes stays on the screen and in the browser, rather than being sent to be
  # refused and rolled back.
  feature "holds a write made in a tab the server stopped serving", %{session: session} do
    session
    |> visit(StoppedTabPage)
    |> mark_this_page_load()
    |> stop()
    |> count_mutation_requests()
    |> click(button("Create alpha"))
    |> assert_text(css("#todos"), "alpha")
    |> await_durable_writes()
    |> await_pending_writes(1)
    |> assert_mutation_requests(0)
    |> assert_text(css("#todos"), "alpha")
    |> assert_same_page_load()

    assert DB.read(Todo) == []
  end

  # The write reaches the server before the stream does, and the refusal is what stops the tab.
  feature "holds a write the server refused for the bundle and stops the tab", %{session: session} do
    session =
      session
      |> visit(StoppedTabPage)
      |> mark_this_page_load()
      |> make_stale()
      |> click(button("Create alpha"))
      |> assert_has(notice())
      |> assert_text(css("#todos"), "alpha")

    await_pending_writes(session, 1)

    assert DB.read(Todo) == []

    assert_same_page_load(session)
  end

  # The server checks only the model on a write, so a tab stopped over the protocol alone still
  # sends what the person writes.
  feature "sends the writes of a tab the server stopped over its protocol", %{session: session} do
    session =
      session
      |> visit(StoppedTabPage)
      |> make_stale("protocolVersion", "0")

    simulate_sse_disconnect(current_instance_id(session))

    session
    |> assert_has(notice())
    |> click(button("Create alpha"))

    assert [%Todo{title: "alpha"}] = await_server_todos(1)
  end

  feature "reloads the page when the person asks for it", %{session: session} do
    session
    |> visit(StoppedTabPage)
    |> stop()
    |> click(button("Create alpha"))
    |> assert_text(css("#todos"), "alpha")
    |> mark_document()
    |> click(button("Reload"))
    |> wait_for_unmarked_document()
    |> assert_page(StoppedTabPage)

    assert [%Todo{title: "alpha"}] = await_server_todos(1)

    refute_has(session, css("#hologram-reload-notice"))
  end

  # Put away for the rest of the page's life, however many renders follow.
  feature "puts the notice away when the person dismisses it", %{session: session} do
    session
    |> visit(StoppedTabPage)
    |> mark_this_page_load()
    |> stop()
    |> click(css("#hologram-reload-notice button[aria-label='Dismiss']"))
    |> refute_has(css("#hologram-reload-notice"))
    |> click(button("Create alpha"))
    |> assert_text(css("#todos"), "alpha")
    |> refute_has(css("#hologram-reload-notice"))
    |> assert_same_page_load()
  end

  # The next page would run the code the server can no longer serve.
  feature "loads the page a link leads to afresh", %{session: session} do
    session
    |> visit(StoppedTabPage)
    |> stop()
    |> mark_document()
    |> click(link("Write queue link"))
    |> wait_for_unmarked_document()
    |> assert_page(WriteQueuePage)
  end

  feature "loads the page an action names afresh", %{session: session} do
    session
    |> visit(StoppedTabPage)
    |> stop()
    |> mark_document()
    |> click(button("Go to the write queue"))
    |> wait_for_unmarked_document()
    |> assert_page(WriteQueuePage)
  end

  feature "loads the page Back leads to afresh", %{session: session} do
    session
    |> visit(StoppedTabPage)
    |> click(link("Write queue link"))
    |> assert_page(WriteQueuePage)
    |> stop()
    |> mark_document()
    |> execute_script("history.back();")
    |> wait_for_unmarked_document()
    |> assert_page(StoppedTabPage)
  end

  # The tab that follows has no stream of its own, so it learns from the tab that leads.
  feature "shows the notice in every tab of the browser", %{session: session} do
    leading = visit(session, StoppedTabPage)
    first = tab_handle(leading)

    following = open_tab(leading, StoppedTabPage)
    second = tab_handle(following)

    following
    |> focus_tab(first)
    |> stop()
    |> focus_tab(second)
    |> assert_has(notice())
  end

  # The frame that said so went out before this tab was listening, so it learns from what the tab
  # that leads tells a tab joining.
  feature "shows the notice in a tab opened after the stop", %{session: session} do
    session
    |> visit(StoppedTabPage)
    |> stop()
    |> open_tab(StoppedTabPage)
    |> assert_has(notice())
  end
end
