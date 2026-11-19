defmodule HologramFeatureTests.ForeignSessionTest do
  # async: false - each test truncates the shared tables.
  use HologramFeatureTests.TestCase, async: false

  require Hologram.Query

  alias Hologram.Auth.RoleGrant
  alias Hologram.DB
  alias Hologram.Query
  alias HologramFeatureTests.Entities.GuestEntry
  alias HologramFeatureTests.ForeignSessionPage

  setup do
    await_evaluator_drain()
    truncate_every_entity_table()

    :ok
  end

  # The browser learns who is signed in when a page mounts, so the page is reloaded after the
  # sign-in command. Wallaby treats visiting the URL the browser already holds as a no-op. The old
  # document passes assert_page/2 too, so the result it showed is what tells the reload landed.
  defp sign_in(session) do
    session
    |> visit(ForeignSessionPage)
    |> click(button("Sign in with an app id"))
    |> assert_text(css("#result"), "signed_in")
    |> reload()
    |> assert_page(ForeignSessionPage)
    |> assert_text(css("#result"), "none")
  end

  defp await_server_entries(text) do
    Enum.reduce_while(1..100, [], fn _attempt, _acc ->
      entries =
        GuestEntry
        |> Query.filter(text: ^text)
        |> DB.read()

      if entries == [] do
        Process.sleep(50)
        {:cont, entries}
      else
        {:halt, entries}
      end
    end)
  end

  defp grants_on(entry) do
    RoleGrant
    |> Query.filter(entity_id: ^entry.id)
    |> DB.read()
  end

  feature "writes a row from the browser of a session signed in with an app's own user id", %{
    session: session
  } do
    session
    |> sign_in()
    |> click(button("Write in the browser"))
    |> assert_text(css("#result"), "written_in_browser")
    |> await_pending_writes(0)

    assert [%GuestEntry{} = entry] = await_server_entries("browser")
    assert grants_on(entry) == []
  end

  feature "writes a row from a command of a session signed in with an app's own user id", %{
    session: session
  } do
    session
    |> sign_in()
    |> click(button("Write on the server"))
    |> assert_text(css("#result"), "written_on_server")

    assert [%GuestEntry{} = entry] = await_server_entries("server")
    assert grants_on(entry) == []
  end
end
