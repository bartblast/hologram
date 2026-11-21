defmodule HologramFeatureTests.SessionUserTest do
  # async: false - each test truncates the shared tables.
  use HologramFeatureTests.TestCase, async: false

  alias Hologram.DB
  alias HologramFeatureTests.EmptyPage
  alias HologramFeatureTests.Entities.User
  alias HologramFeatureTests.SessionUserPage

  setup do
    truncate_every_entity_table()

    :ok
  end

  # The browser learns who is signed in when a page mounts, so the page is reloaded after the login
  # command. Wallaby treats visiting the URL the browser already holds as a no-op.
  defp log_in(session) do
    session
    |> visit(SessionUserPage)
    |> click(button("Log in"))
    |> assert_text(css("#result"), "logged_in")
    |> reload()
    |> assert_page(SessionUserPage)
    |> assert_text(css("#session_user"), "session_user@example.com")
  end

  feature "renders the anonymous text for an anonymous session", %{session: session} do
    session
    |> visit(SessionUserPage)
    |> assert_text(css("#session_user"), "anonymous")
  end

  feature "shows a change the browser makes to the session user's row on the same page load", %{
    session: session
  } do
    session
    |> log_in()
    |> mark_this_page_load()
    |> click(button("Rename locally"))
    |> assert_text(css("#session_user"), "renamed_locally@example.com")
    |> assert_same_page_load()
    |> await_pending_writes(0)

    assert [%User{email: "renamed_locally@example.com"}] = DB.read(User)
  end

  feature "shows a change the server makes to the session user's row on the same page load", %{
    session: session
  } do
    # The fill would bring a write made before it too, so the write waits for it, and so reaches
    # the page as a live change.
    session =
      session
      |> log_in()
      |> await_local_fill()
      |> mark_this_page_load()

    [user] = DB.read(User)

    DB.update!(User, user.id, email: "renamed_on_server@example.com")

    session
    |> assert_text(css("#session_user"), "renamed_on_server@example.com")
    |> assert_same_page_load()
  end

  # The marker is state only the page as it was left holds, so seeing it says Back restored the
  # page's snapshot rather than rendering the page afresh. The document mark says the browser
  # loaded a new document for it rather than bringing the old one back from its back/forward
  # cache.
  feature "shows the session user on a page Back restores after a full page load", %{
    session: session
  } do
    session
    |> log_in()
    |> click(button("Put marker"))
    |> assert_text(css("#result"), "marked")
    |> mark_document()
    |> visit(EmptyPage)
    |> go_back()
    |> assert_page(SessionUserPage)
    |> wait_for_unmarked_document()
    |> assert_text(css("#result"), "marked")
    |> assert_text(css("#session_user"), "session_user@example.com")
  end
end
