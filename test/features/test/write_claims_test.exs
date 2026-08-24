defmodule HologramFeatureTests.WriteClaimsTest do
  use HologramFeatureTests.TestCase, async: false

  alias Hologram.Auth.RoleGrant
  alias Hologram.DB
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias HologramFeatureTests.Entities.Note
  alias HologramFeatureTests.Entities.User
  alias HologramFeatureTests.WriteClaimsPage

  # All three tables truncate in one statement: the role grant table's foreign keys to the
  # user table make Postgres reject truncating the referenced table alone.
  setup do
    tables =
      Enum.map_join([Note, RoleGrant, User], ", ", fn entity_type ->
        ~s("hologram_data"."#{Mapper.table_name(entity_type)}")
      end)

    {:ok, _result} = Connection.query("TRUNCATE #{tables}", [])

    :ok
  end

  defp log_in(session) do
    session
    |> visit(WriteClaimsPage)
    |> click(button("Log in"))
    |> assert_text(css("#result"), "logged_in")
  end

  defp session_user do
    User
    |> DB.read()
    |> Enum.find(&(&1.email == "session@example.com"))
  end

  feature "adds a note on the acting user's authority when the rule's predicate holds on the new row",
          %{session: session} do
    session
    |> log_in()
    |> click(button("Add note as author"))
    |> assert_text(css("#result"), "added_note_as_author")

    assert [%Note{body: "own"} = note] = DB.read(Note)
    assert note.author_id == session_user().id
  end

  feature "adds a note on the server's authority", %{session: session} do
    session
    |> log_in()
    |> click(button("Add note by server"))
    |> assert_text(css("#result"), "added_note_by_server")

    assert [%Note{body: "by server"}] = DB.read(Note)
  end

  feature "denies a note claimed for a user who is not its author", %{session: session} do
    session
    |> log_in()
    |> click(button("Add note as other"))
    |> assert_text(
      css("#result"),
      ~r/^not allowed to create HologramFeatureTests\.Entities\.Note /
    )

    assert DB.read(Note) == []
  end

  feature "denies pinning a note the current row already shows pinned", %{session: session} do
    session
    |> log_in()
    |> click(button("Pin pinned note"))
    |> assert_text(css("#result"), ~r/^not allowed to pin HologramFeatureTests\.Entities\.Note /)
  end

  feature "deletes a note on its owner's authority", %{session: session} do
    session
    |> log_in()
    |> click(button("Delete own note"))
    |> assert_text(css("#result"), "deleted_own_note")

    assert DB.read(Note) == []
  end

  feature "pins a note on an editor's authority", %{session: session} do
    session
    |> log_in()
    |> click(button("Pin note"))
    |> assert_text(css("#result"), "pinned_note")

    assert [%Note{pinned: true}] = DB.read(Note)
  end

  feature "refuses an update that recorded nothing", %{session: session} do
    session
    |> log_in()
    |> click(button("Update unrecorded note"))
    |> assert_text(css("#result"), ~r/^update takes recorded changes/)

    assert [%Note{pinned: false}] = DB.read(Note)
  end
end
