defmodule HologramFeatureTests.CatchupTest do
  # async: false - each test truncates the shared tables.
  use HologramFeatureTests.TestCase, async: false

  import Hologram.DB.EntityOperations, only: [update: 3]

  alias Hologram.DB
  alias Hologram.Realtime.SSE
  alias Hologram.Sync.Sessions
  alias HologramFeatureTests.Entities.Document
  alias HologramFeatureTests.Entities.Folder
  alias HologramFeatureTests.SyncPage

  @max_wait_time Application.compile_env(:wallaby, :max_wait_time, 3_000)

  # The browser end of a returning client's catch-up, which `sync_test.exs` checks on the wire.
  #
  # The lever is a stream killed while its next attach is held back by a cookie: the change written
  # meanwhile reaches nothing this browser can hear, and the attach after it starts a returning
  # client's session, so what the browser holds afterwards can only have come through the
  # catch-up.
  setup do
    truncate_every_entity_table()

    :ok
  end

  defp away_while(session, change) do
    hold_attach(session, 2_000)

    session
    |> current_instance_id()
    |> simulate_sse_disconnect()

    change.()

    session
  end

  defp hold_attach(session, delay_ms) do
    Wallaby.Browser.set_cookie(session, SSE.attach_delay_cookie(), to_string(delay_ms))
  end

  # The session that caught the browser up is one that came back with a place, which is the only
  # kind that hashes drops - a client sent everything again would have its rows refilled instead.
  defp assert_caught_up(session, attempts_left \\ 100)

  defp assert_caught_up(_session, 0) do
    flunk("no session that came back with a place is serving the browser")
  end

  defp assert_caught_up(session, attempts_left) do
    case Sessions.list() do
      [{pid, _user_id}] ->
        assert :sys.get_state(pid).drop_salt != nil

        session

      _none_or_more ->
        Process.sleep(50)
        assert_caught_up(session, attempts_left - 1)
    end
  end

  # The document is readable only through its folder: it isn't public, and nobody holds a role on
  # it. The server rebuilds what the browser holds from what its user may read now, which no
  # longer takes the document in, so it names it by hash - and only a browser holding it can tell
  # which row that is.
  #
  # After the reload the stream is held back for longer than the test reads, so what the page
  # reads - its place, the folder that stays readable, and no document - can only have come out
  # of the browser's own store. The hold outlasts the fill wait too: a browser that lost its place
  # would otherwise have it handed back by a fill from the server just before the wait gives up.
  feature "drops a row its folder going private hid while away, for good", %{session: session} do
    folder =
      %{name: "shut_folder", public: true}
      |> Folder.new()
      |> DB.create!()

    %{name: "kept_folder", public: true}
    |> Folder.new()
    |> DB.create!()

    %{folder_id: folder.id, public: false, title: "points_at_the_folder"}
    |> Document.new()
    |> DB.create!()

    await_log_settled()

    session
    |> visit(SyncPage)
    |> await_local_fill()
    |> await_local_read("Read the document's folder locally", "local_document_folder", "linked")
    |> away_while(fn -> update(Folder, folder.id, %{public: false}) end)
    |> await_local_read("Read the document's folder locally", "local_document_folder", "missing")
    |> assert_caught_up()
    |> await_durable_writes()
    |> hold_attach(2 * @max_wait_time)
    |> mark_document()
    |> reload()
    |> wait_for_unmarked_document()
    |> await_local_fill()
    |> click(button("Read folder locally"))
    |> assert_text(css("#local_folder"), "kept_folder")
    |> click(button("Read the document's folder locally"))
    |> assert_text(css("#local_document_folder"), "missing")
  end

  feature "hands over a row its folder going public opened while away", %{session: session} do
    folder =
      %{name: "kept_folder", public: false}
      |> Folder.new()
      |> DB.create!()

    %{folder_id: folder.id, public: false, title: "points_at_the_folder"}
    |> Document.new()
    |> DB.create!()

    await_log_settled()

    session
    |> visit(SyncPage)
    |> await_local_fill()
    |> await_local_read("Read the document's folder locally", "local_document_folder", "missing")
    |> away_while(fn -> update(Folder, folder.id, %{public: true}) end)
    |> await_local_read("Read the document's folder locally", "local_document_folder", "linked")
    |> assert_caught_up()
  end
end
