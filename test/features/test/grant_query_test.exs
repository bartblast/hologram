defmodule HologramFeatureTests.GrantQueryTest do
  use HologramFeatureTests.TestCase, async: false

  alias Hologram.Auth
  alias Hologram.Auth.RoleGrant
  alias Hologram.DB
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias HologramFeatureTests.Entities.Document
  alias HologramFeatureTests.Entities.Folder
  alias HologramFeatureTests.Entities.Note
  alias HologramFeatureTests.Entities.User
  alias HologramFeatureTests.GrantQueryPage

  # All the tables truncate in one statement: the role grant table's foreign keys to the user
  # table make Postgres reject truncating the referenced table alone.
  setup do
    tables =
      Enum.map_join([Document, Folder, Note, RoleGrant, User], ", ", fn entity_type ->
        ~s("hologram_data"."#{Mapper.table_name(entity_type)}")
      end)

    {:ok, _result} = Connection.query("TRUNCATE #{tables}", [])

    document =
      %{title: "queried_document"}
      |> Document.new()
      |> DB.create!()

    third_user =
      %{email: "third@example.com"}
      |> User.new()
      |> DB.create!()

    {:ok, document: document, third_user: third_user}
  end

  defp create_user(email) do
    %{email: email}
    |> User.new()
    |> DB.create!()
  end

  defp session_user do
    User
    |> DB.read()
    |> Enum.find(&(&1.email == "session@example.com"))
  end

  defp stored_role(user_id) do
    grant =
      RoleGrant
      |> DB.read()
      |> Enum.find(&(&1.user_id == user_id))

    grant && grant.role
  end

  # A command changes the session and not the page already mounted, so a page mounted before this
  # holds no user id - every caller reloads.
  defp sign_in(session) do
    session
    |> visit(GrantQueryPage)
    |> click(button("Log in"))
    |> assert_text(css("#result"), "logged_in")
  end

  # Signs the session in and makes its user the document's owner as trusted code, then reloads:
  # the reload is what makes the page hold the session user, and what fills the browser with the
  # grants that user may now read - their own, and everyone else's on the document, since
  # Editable's grant and revoke lines are what qualify a reader where no read_roles line does.
  defp sign_in_as_owner(session, document) do
    sign_in(session)

    Auth.grant_role(session_user(), document, :owner)

    session
    |> reload()
    |> assert_page(GrantQueryPage)
    |> assert_text(css("#grants"), "owner:#{session_user().id}")
  end

  feature "reads the grants on an entity by the entity's own type", %{
    session: session,
    document: document
  } do
    editor = create_user("editor@example.com")
    owner = create_user("owner@example.com")

    Auth.grant_role(editor, document, :editor)
    Auth.grant_role(owner, document, :owner)

    session = sign_in(session)

    Auth.grant_role(session_user(), document, :owner)

    # Asserted per row rather than as one string: two grants written a moment apart can carry the
    # same created_at on a coarse clock, so the order between them is undefined and only their
    # presence is a claim worth making.
    session
    |> reload()
    |> assert_page(GrantQueryPage)
    |> assert_text(css("#grants"), "editor:#{editor.id}")
    |> assert_text(css("#grants"), "owner:#{owner.id}")
  end

  # The other half of the same claim: the label the BROWSER writes into a grant is the one this
  # query compares against, and the one the server stores. The row is in the list before anything
  # is sent, and the server agrees once it lands.
  feature "gains a grant the browser makes, before the server has heard of it", %{
    session: session,
    document: document,
    third_user: third_user
  } do
    session
    |> sign_in_as_owner(document)
    |> hold_mutation_requests()
    |> click(button("Share with the third user"))
    |> assert_text(css("#result"), "share_ok")
    |> assert_text(css("#grants"), "editor:#{third_user.id}")

    # Nothing has reached the server while the request is held.
    assert stored_role(third_user.id) == nil

    session
    |> release_mutations()
    |> await_pending_writes(0)

    assert stored_role(third_user.id) == :editor
  end
end
