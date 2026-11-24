defmodule HologramFeatureTests.IdentityChangeTest do
  # async: false - each test truncates the shared tables.
  use HologramFeatureTests.TestCase, async: false

  alias Hologram.DB
  alias HologramFeatureTests.Entities.Memo
  alias HologramFeatureTests.Entities.Note
  alias HologramFeatureTests.Entities.User
  alias HologramFeatureTests.IdentityChangePage

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
end
