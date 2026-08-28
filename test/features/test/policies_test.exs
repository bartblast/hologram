defmodule HologramFeatureTests.PoliciesTest do
  use HologramFeatureTests.TestCase, async: false

  alias Hologram.Auth.RoleGrant
  alias Hologram.DB
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias HologramFeatureTests.Entities.Document
  alias HologramFeatureTests.Entities.Folder
  alias HologramFeatureTests.Entities.Note
  alias HologramFeatureTests.Entities.User
  alias HologramFeatureTests.PoliciesPage

  # All four tables truncate in one statement: the role grant table's foreign keys to the
  # user table make Postgres reject truncating the referenced table alone.
  setup do
    tables =
      Enum.map_join([Document, Folder, Note, RoleGrant, User], ", ", fn entity_type ->
        ~s("hologram_data"."#{Mapper.table_name(entity_type)}")
      end)

    {:ok, _result} = Connection.query("TRUNCATE #{tables}", [])

    :ok
  end

  feature "renders only unconditionally readable rows for an anonymous session", %{
    session: session
  } do
    %{public: true, title: "public_document"}
    |> Document.new()
    |> DB.create!()

    %{title: "private_document"}
    |> Document.new()
    |> DB.create!()

    session
    |> visit(PoliciesPage)
    |> assert_text(css("#documents"), "public_document")
    |> refute_has(css("#documents", text: "private_document"))
    |> assert_text(css("#session_user"), "anonymous")
  end

  feature "renders an included row only when the session may read it", %{session: session} do
    public_folder =
      %{name: "shared_folder", public: true}
      |> Folder.new()
      |> DB.create!()

    private_folder =
      %{name: "locked_folder"}
      |> Folder.new()
      |> DB.create!()

    %{folder_id: public_folder.id, public: true, title: "filed_document"}
    |> Document.new()
    |> DB.create!()

    %{folder_id: private_folder.id, public: true, title: "secret_document"}
    |> Document.new()
    |> DB.create!()

    session
    |> visit(PoliciesPage)
    |> assert_text(css("#documents"), "filed_document,secret_document")
    |> assert_text(css("#folders"), "shared_folder,none")
  end

  # The page is reloaded rather than revisited: Wallaby navigates to the URL the browser
  # already holds, which it treats as a no-op, so the row created in between would never
  # reach a render.
  feature "renders a row the session user created, through its creator role grant", %{
    session: session
  } do
    session
    |> visit(PoliciesPage)
    |> click(button("Log in"))
    |> assert_text(css("#result"), "logged_in")
    |> click(button("Create own document"))
    |> assert_text(css("#result"), "created_own_document")
    |> reload()
    |> assert_text(css("#documents"), "own_document")
    |> assert_text(css("#session_user"), "session@example.com")
  end

  feature "grants a role on a resource the session user manages", %{session: session} do
    session
    |> visit(PoliciesPage)
    |> click(button("Log in"))
    |> assert_text(css("#result"), "logged_in")
    |> click(button("Grant editor"))
    |> assert_text(css("#result"), "grant_editor_true")
  end

  feature "reads every row on the server's authority", %{session: session} do
    %{title: "hidden_document"}
    |> Document.new()
    |> DB.create!()

    %{public: true, title: "public_document"}
    |> Document.new()
    |> DB.create!()

    session
    |> visit(PoliciesPage)
    |> click(button("Log in"))
    |> assert_text(css("#result"), "logged_in")
    |> click(button("Read documents as server"))
    |> assert_text(css("#result"), "read_as_server_hidden_document,public_document")
  end

  feature "reads only the rows the session user may read", %{session: session} do
    %{title: "hidden_document"}
    |> Document.new()
    |> DB.create!()

    %{public: true, title: "public_document"}
    |> Document.new()
    |> DB.create!()

    session
    |> visit(PoliciesPage)
    |> click(button("Log in"))
    |> assert_text(css("#result"), "logged_in")
    |> click(button("Read documents as user"))
    |> assert_text(css("#result"), "read_as_user_public_document")
  end

  feature "revokes a role it granted", %{session: session} do
    session
    |> visit(PoliciesPage)
    |> click(button("Log in"))
    |> assert_text(css("#result"), "logged_in")
    |> click(button("Revoke editor"))
    |> assert_text(css("#result"), "revoke_editor_false")
  end

  feature "refuses to revoke the last role managing a resource", %{session: session} do
    session
    |> visit(PoliciesPage)
    |> click(button("Log in"))
    |> assert_text(css("#result"), "logged_in")
    |> click(button("Leave last owner"))
    |> assert_text(css("#result"), "cannot revoke the last role managing")
  end
end
