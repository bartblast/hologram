defmodule HologramFeatureTests.OptimisticGrantsTest do
  use HologramFeatureTests.TestCase, async: false

  alias Hologram.Auth
  alias Hologram.Auth.RoleGrant
  alias Hologram.DB
  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias HologramFeatureTests.Entities.Document
  alias HologramFeatureTests.Entities.Folder
  alias HologramFeatureTests.Entities.Note
  alias HologramFeatureTests.Entities.User
  alias HologramFeatureTests.OptimisticGrantsPage

  # All the tables truncate in one statement: the role grant table's foreign keys to the user
  # table make Postgres reject truncating the referenced table alone.
  setup do
    tables =
      Enum.map_join([Document, Folder, Note, RoleGrant, User], ", ", fn entity_type ->
        ~s("hologram_data"."#{Mapper.table_name(entity_type)}")
      end)

    {:ok, _result} = Connection.query("TRUNCATE #{tables}", [])

    document =
      %{title: "shared_document"}
      |> Document.new()
      |> DB.create!()

    other_user =
      %{email: "other@example.com"}
      |> User.new()
      |> DB.create!()

    {:ok, document: document, other_user: other_user}
  end

  defp session_user do
    User
    |> DB.read()
    |> Enum.find(&(&1.email == "session@example.com"))
  end

  defp grants(user_id) do
    RoleGrant
    |> DB.read()
    |> Enum.filter(&(&1.user_id == user_id))
    |> Enum.map(& &1.role)
    |> Enum.sort()
  end

  # A command changes the session and not the page already mounted, so a page mounted before this
  # holds no user id - every caller reloads.
  defp sign_in(session) do
    session
    |> visit(OptimisticGrantsPage)
    |> click(button("Log in"))
    |> assert_text(css("#result"), "logged_in")
  end

  # Signs the session in and gives its user the given role on the document as trusted code, then
  # reloads: the reload is what makes the page hold the session user, and what fills it with the
  # grants that user now has.
  defp sign_in_as(session, document, role) do
    sign_in(session)

    Auth.grant_role(session_user(), document, role)

    session
    |> reload()
    |> assert_page(OptimisticGrantsPage)
    |> assert_text(css("#grants"), "#{role}:#{session_user().id}")
  end

  feature "shows a granted role before the server answers", %{
    session: session,
    document: document,
    other_user: other_user
  } do
    session
    |> sign_in_as(document, :owner)
    |> hold_mutation_requests()
    |> click(button("Grant editor"))
    |> assert_text(css("#result"), "grant_editor_ok")
    |> assert_text(css("#grants"), "editor:#{other_user.id}")

    # Nothing has reached the server while the request is held.
    assert grants(other_user.id) == []

    session
    |> release_mutations()
    |> await_pending_writes(0)

    assert grants(other_user.id) == [:editor]
  end

  feature "queues a grant made offline", %{
    session: session,
    document: document,
    other_user: other_user
  } do
    session
    |> sign_in_as(document, :owner)
    |> hold_mutation_requests()
    |> click(button("Grant editor"))
    |> assert_text(css("#grants"), "editor:#{other_user.id}")
    |> await_pending_writes(1)
    |> await_durable_writes()
    |> reload()
    |> assert_page(OptimisticGrantsPage)
    |> assert_text(css("#grants"), "editor:#{other_user.id}")
    |> await_pending_writes(0)

    assert grants(other_user.id) == [:editor]
  end

  # The session user holds nothing anywhere before the click: the note the action makes is what
  # hands them its :owner role, and the share on the next line is what needs it. Both grants ride
  # the create's own batch, and the server writes the creator's one itself when that batch lands -
  # under the id this browser derived, which is why the store ends with one owner row and not two.
  feature "puts someone on a row it just made", %{
    session: session,
    other_user: other_user
  } do
    session
    |> sign_in()
    |> reload()
    |> assert_page(OptimisticGrantsPage)
    |> hold_mutation_requests()
    |> click(button("Create and share"))
    |> assert_text(css("#result"), "create_and_share_ok")
    |> assert_text(css("#grants"), "editor:#{other_user.id}")

    # Nothing has reached the server while the request is held.
    assert grants(other_user.id) == []

    session
    |> release_mutations()
    |> await_pending_writes(0)

    assert grants(other_user.id) == [:editor]
    assert grants(session_user().id) == [:owner]
  end

  # The browser's gate reads the same rules the server does, so an escalation is refused before
  # anything is sent - and the store is untouched.
  feature "refuses an escalation in the browser without sending anything", %{
    session: session,
    document: document,
    other_user: other_user
  } do
    session
    |> sign_in_as(document, :editor)
    |> click(button("Grant owner"))
    |> assert_text(css("#result"), "grant_owner_refused")
    |> await_pending_writes(0)

    assert grants(other_user.id) == []
  end

  # The stale-client case. The session user's owner row is removed from the store with a raw
  # DELETE, which writes nothing to the log - so the browser is never told and keeps judging by a
  # row the server no longer has. Its gate lets the revocation through; the server's refuses it,
  # and the batch rolls back.
  feature "brings a revoked role back when the server refuses", %{
    session: session,
    document: document,
    other_user: other_user
  } do
    Auth.grant_role(other_user, document, :editor)

    session = sign_in_as(session, document, :owner)

    owner_grant_id =
      RoleGrant.derive_id(
        session_user().id,
        RoleGrant.resource_type(Document),
        document.id,
        :owner
      )

    {:ok, _result} =
      Connection.query(
        ~s|DELETE FROM "hologram_data"."hologram_role_grant" WHERE "id" = $1|,
        [Codec.encode(owner_grant_id, :uuid)]
      )

    session
    |> hold_mutation_requests()
    |> click(button("Revoke editor"))
    |> assert_text(css("#result"), "revoke_editor_ok")
    |> refute_has(css("#grants", text: "editor:#{other_user.id}"))
    |> release_mutations()

    assert [%{"write" => 0}] = await_rejected_writes(session)

    assert_text(session, css("#grants"), "editor:#{other_user.id}")

    assert grants(other_user.id) == [:editor]
  end

  feature "hides a revoked role before the server answers", %{
    session: session,
    document: document,
    other_user: other_user
  } do
    Auth.grant_role(other_user, document, :owner)

    session = sign_in_as(session, document, :editor)

    session
    |> hold_mutation_requests()
    |> click(button("Leave"))
    |> assert_text(css("#result"), "leave_ok")
    |> refute_has(css("#grants", text: "editor:#{session_user().id}"))

    assert grants(session_user().id) == [:editor]

    session
    |> release_mutations()
    |> await_pending_writes(0)

    assert grants(session_user().id) == []
  end

  feature "revokes another user's role", %{
    session: session,
    document: document,
    other_user: other_user
  } do
    Auth.grant_role(other_user, document, :editor)

    session
    |> sign_in_as(document, :owner)
    |> click(button("Revoke editor"))
    |> assert_text(css("#result"), "revoke_editor_ok")
    |> await_pending_writes(0)

    assert grants(other_user.id) == []
  end
end
