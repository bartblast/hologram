defmodule HologramFeatureTests.IdentityChangeTest do
  # async: false - each test truncates the shared tables.
  use HologramFeatureTests.TestCase, async: false

  alias Hologram.DB
  alias Hologram.Realtime.SSE
  alias HologramFeatureTests.Entities.Memo
  alias HologramFeatureTests.Entities.Note
  alias HologramFeatureTests.Entities.User
  alias HologramFeatureTests.IdentityChangePage
  alias HologramFeatureTestsWeb.Plugs.SlowPageBundle

  @stream_connected_script "return globalThis.Hologram?.['sseConnected?'];"

  # Each user reads only the memos they wrote, so what a tab lists says whose rows it holds.
  setup do
    truncate_every_entity_table()

    ann = create_user("ann@example.com")
    bob = create_user("bob@example.com")

    create_memo(ann, "ann_memo")
    create_memo(bob, "bob_memo")

    %{bob: bob}
  end

  defp create_memo(author, body) do
    %{author_id: author.id, body: body}
    |> Memo.new()
    |> DB.create!()
  end

  defp create_user(email) do
    %{email: email}
    |> User.new()
    |> DB.create!()
  end

  # Starts each test from a page mounted as Ann. Past it, nothing reloads the page: the tab learns
  # of each change of user from the server, and the page load marked here is still the one shown
  # at the end. The tab follows the login before the reload, so the document mark is what says the
  # reload landed.
  defp log_in_as_ann(session) do
    session
    |> visit(IdentityChangePage)
    |> click(button("Log in as Ann"))
    |> assert_text(css("#result"), "logged_in_as_ann")
    |> mark_document()
    |> reload()
    |> wait_for_unmarked_document()
    |> assert_page(IdentityChangePage)
    |> assert_text(css("#session_user"), "ann@example.com")
    |> assert_text(css("#memos"), ~r/\Aann_memo\z/)
    |> mark_this_page_load()
  end

  defp session_cookie(session) do
    %{"value" => value} =
      session
      |> cookies()
      |> Enum.find(&(&1["name"] == "phoenix_session"))

    value
  end

  # Records every time the page shows another user, or rows other than the given ones. Once the
  # page has shown the user with their rows, a page without either counts too.
  defp watch_for_other_rows(session, email, memos) do
    script = """
    const [email, memos] = arguments;
    globalThis.__otherRows = [];
    let shown = false;

    const check = () => {
      const shownEmail = document.querySelector("#session_user")?.textContent.trim();
      const shownMemos = document.querySelector("#memos")?.textContent.trim();

      if (shownEmail === email && shownMemos === memos) {
        shown = true;
      } else if (shown || (shownEmail ?? email) !== email || (shownMemos ?? memos) !== memos) {
        globalThis.__otherRows.push([shownEmail, shownMemos]);
      }
    };

    new MutationObserver(check).observe(document.documentElement, {
      characterData: true,
      childList: true,
      subtree: true,
    });

    check();
    """

    execute_script(session, script, [email, memos])
  end

  defp await_server_notes(attempts_left \\ 100) do
    case DB.read(Note) do
      [] when attempts_left > 0 ->
        Process.sleep(50)
        await_server_notes(attempts_left - 1)

      notes ->
        notes
    end
  end

  defp assert_serves_bob(session) do
    session
    |> assert_text(css("#session_user"), "bob@example.com")
    |> assert_text(css("#memos"), ~r/\Abob_memo\z/)
  end

  defp assert_serves_nobody(session) do
    session
    |> assert_text(css("#session_user"), "anonymous")
    |> assert_text(css("#memos"), ~r/\A\z/)
  end

  # The server takes the note only from its author, so it lands only if the tab and the server
  # both take the session user to be the given one.
  defp assert_wrote_as(session, user) do
    click(session, button("Write note"))

    assert [%Note{author_id: author_id}] = await_server_notes()
    assert author_id == user.id

    session
  end

  feature "follows a login in the tab that logs in", %{session: session, bob: bob} do
    session
    |> visit(IdentityChangePage)
    |> assert_serves_nobody()
    |> mark_this_page_load()
    |> click(button("Log in as Bob"))
    |> assert_text(css("#result"), "logged_in_as_bob")
    |> assert_serves_bob()
    |> assert_wrote_as(bob)
    |> assert_same_page_load()
  end

  feature "follows a change of user in the tab that makes it", %{session: session, bob: bob} do
    session
    |> log_in_as_ann()
    |> click(button("Log in as Bob"))
    |> assert_text(css("#result"), "logged_in_as_bob")
    |> assert_serves_bob()
    |> assert_wrote_as(bob)
    |> assert_same_page_load()
  end

  feature "follows a change of user made in another tab", %{session: session, bob: bob} do
    first = log_in_as_ann(session)
    first_handle = tab_handle(first)

    first
    |> open_tab(IdentityChangePage)
    |> click(button("Log in as Bob"))
    |> assert_text(css("#result"), "logged_in_as_bob")
    |> assert_serves_bob()
    |> focus_tab(first_handle)
    |> assert_serves_bob()
    |> assert_wrote_as(bob)
    |> assert_same_page_load()
  end

  feature "follows a logout in the tab that logs out", %{session: session} do
    session
    |> log_in_as_ann()
    |> click(button("Log out"))
    |> assert_text(css("#result"), "logged_out")
    |> assert_serves_nobody()
    |> assert_same_page_load()
  end

  feature "follows a logout made in another tab", %{session: session} do
    first = log_in_as_ann(session)
    first_handle = tab_handle(first)

    first
    |> open_tab(IdentityChangePage)
    |> click(button("Log out"))
    |> assert_text(css("#result"), "logged_out")
    |> assert_serves_nobody()
    |> focus_tab(first_handle)
    |> assert_serves_nobody()
    |> assert_same_page_load()
  end

  # The page Back goes to comes from its snapshot, which carries no mount data, so the reloaded
  # document has to tell the data layer who it was rendered for before that page mounts. The
  # destination's bundle is held back from the navigation on, so the reload fetches it afresh
  # rather than finding it in the browser's cache, and the destination's own script presses Back
  # before it arrives (see IdentityChangeDestinationPage).
  feature "keeps the user and their rows on a Back before the reloaded page mounts", %{
    session: session
  } do
    session
    |> log_in_as_ann()
    |> await_durable_writes()
    |> click(button("Put marker"))
    |> assert_text(css("#result"), "marked")
    |> set_cookie(SlowPageBundle.cookie(), "4000")
    |> click(link("Destination link"))
    |> assert_has(css("#destination_title"))
    |> execute_script(
      ~s/sessionStorage.setItem("hologram_back_before_mount", JSON.stringify(arguments[0]));/,
      [["ann@example.com", "ann_memo"]]
    )
    |> mark_document()
    |> reload()
    |> wait_for_unmarked_document()
    |> await_script("return globalThis.__mountedBeforeBack !== undefined;")
    |> assert_script_result("return globalThis.__mountedBeforeBack;", false)
    |> assert_page(IdentityChangePage)
    |> assert_text(css("#result"), "marked")
    |> mark_this_page_load()
    |> assert_text(css("#session_user"), "ann@example.com")
    |> assert_text(css("#memos"), ~r/\Aann_memo\z/)
    |> await_local_fill()
    |> assert_script_result("return globalThis.__otherRows;", [])
    |> assert_same_page_load()
  end

  # Bob's two tabs open together over the store Ann's tab filled, with their reads of it held, so
  # the one that leads refuses Ann's rows while the other has taken up the rows its page carried.
  # Both tabs are Bob's, so neither may show anything but Bob and his rows, at any point.
  #
  # Passes before #1655 too: the drop it watches for is too brief to render here, so the unit tests
  # in durability_test.mjs and tabs_test.mjs are what fail without the fix. This one guards the
  # whole path.
  @sessions 2
  feature "keeps the rows a tab carried when another tab of its user refuses the store", %{
    sessions: [session, bob_session]
  } do
    bob_cookie =
      bob_session
      |> visit(IdentityChangePage)
      |> click(button("Log in as Bob"))
      |> assert_text(css("#result"), "logged_in_as_bob")
      |> session_cookie()

    ann =
      session
      |> log_in_as_ann()
      |> await_durable_writes()

    first = tab_handle(ann)

    leading =
      ann
      |> set_cookie("phoenix_session", bob_cookie)
      |> block_store()
      |> open_tab_unmounted(IdentityChangePage)
      |> watch_for_other_rows("bob@example.com", "bob_memo")

    second = tab_handle(leading)

    # The first of Bob's tabs leads his group, and its read of the store is held before the second
    # one opens, so the second follows.
    leading
    |> focus_tab(first)
    |> await_store_read_waiting()
    |> await_leader_locks(:held, 2)

    following =
      leading
      |> open_tab_unmounted(IdentityChangePage)
      |> watch_for_other_rows("bob@example.com", "bob_memo")

    third = tab_handle(following)

    following
    |> focus_tab(first)
    |> await_leader_locks(:pending, 1)
    |> unblock_store()

    for tab <- [second, third] do
      following
      |> focus_tab(tab)
      |> await_page_mount(IdentityChangePage)
      |> await_local_fill()
      |> assert_text(css("#session_user"), "bob@example.com")
      |> assert_text(css("#memos"), ~r/\Abob_memo\z/)
      |> assert_script_result("return globalThis.__otherRows;", [])
    end
  end

  # The anonymous tab's stream is cut and held from coming back until another tab has logged in,
  # so the tab hears of the login from nothing but its reconnect. It must take up Ann as it comes
  # back, rather than go on as a visitor with a stream that now serves Ann.
  feature "follows a change of user a tab's stream missed while it was cut", %{
    session: session
  } do
    anonymous =
      session
      |> visit(IdentityChangePage)
      |> await_local_fill()
      |> assert_text(css("#session_user"), "anonymous")
      |> mark_this_page_load()

    first = tab_handle(anonymous)

    anonymous
    |> set_cookie(SSE.attach_delay_cookie(), "8000")
    |> current_instance_id()
    |> simulate_sse_disconnect()

    logging_in =
      anonymous
      |> open_tab_unmounted(IdentityChangePage)
      |> await_page_mount(IdentityChangePage)

    second = tab_handle(logging_in)

    logging_in
    |> focus_tab(first)
    |> assert_script_result(@stream_connected_script, false)
    |> focus_tab(second)
    |> click(button("Log in as Ann"))
    |> assert_text(css("#result"), "logged_in_as_ann")
    |> focus_tab(first)
    |> assert_text(css("#session_user"), "ann@example.com")
    |> assert_text(css("#memos"), ~r/\Aann_memo\z/)
    |> await_local_fill()
    |> assert_same_page_load()
  end
end
