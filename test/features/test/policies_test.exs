defmodule HologramFeatureTests.PoliciesTest do
  use HologramFeatureTests.TestCase, async: false

  import Hologram.DB.EntityOperations, only: [create: 1]

  alias Hologram.Auth.RoleGrant
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias Hologram.Entity
  alias HologramFeatureTests.EmptyPage
  alias HologramFeatureTests.Entities.Document
  alias HologramFeatureTests.Entities.User
  alias HologramFeatureTests.PoliciesPage

  # All three tables truncate in one statement: the role grant table's foreign keys to the
  # user table make Postgres reject truncating the referenced table alone.
  setup do
    tables =
      Enum.map_join([Document, RoleGrant, User], ", ", fn entity_type ->
        ~s("hologram_data"."#{Mapper.table_name(entity_type)}")
      end)

    {:ok, _result} = Connection.query("TRUNCATE #{tables}", [])

    :ok
  end

  feature "renders only unconditionally readable rows for an anonymous session", %{
    session: session
  } do
    Document
    |> Entity.new(public: true, title: "public_document")
    |> create()

    Document
    |> Entity.new(title: "private_document")
    |> create()

    session
    |> visit(PoliciesPage)
    |> assert_text(css("#documents"), "public_document")
    |> refute_has(css("#documents", text: "private_document"))
    |> assert_text(css("#session_user"), "anonymous")
  end

  # The page is revisited through another page: navigating to the URL the browser already
  # holds does not reload it, so the row created in between would never reach a render.
  feature "renders a row the session user created, through its creator role grant", %{
    session: session
  } do
    session
    |> visit(PoliciesPage)
    |> click(button("Log in"))
    |> assert_text(css("#result"), "logged_in")
    |> click(button("Create own document"))
    |> assert_text(css("#result"), "created_own_document")
    |> visit(EmptyPage)
    |> visit(PoliciesPage)
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
