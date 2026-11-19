defmodule HologramFeatureTests.PermissionChecksTest do
  # async: false - each test truncates the shared tables.
  use HologramFeatureTests.TestCase, async: false

  alias Hologram.Auth
  alias Hologram.Auth.RoleGrant
  alias Hologram.DB
  alias HologramFeatureTests.Entities.Document
  alias HologramFeatureTests.Entities.Memo
  alias HologramFeatureTests.Entities.Note
  alias HologramFeatureTests.Entities.ProjectMember
  alias HologramFeatureTests.Entities.User
  alias HologramFeatureTests.Policies.Page1

  # The other end of the permission check: the policies tests assert what the SERVER answers,
  # and these assert that the CLIENT answers the same - from the rules its build carries and the
  # grant rows its pot holds. Nothing here reloads: a grant is written from the test process, the
  # stream delivers the row, and the gated UI follows.
  setup do
    await_evaluator_drain()

    truncate_entity_tables([Document, Memo, Note, ProjectMember, RoleGrant, User])
  end

  defp create_document(title) do
    %{public: true, title: title}
    |> Document.new()
    |> DB.create!()
  end

  defp session_user do
    User
    |> DB.read()
    |> Enum.find(&(&1.email == "manager@example.com"))
  end

  feature "shows what a grant arriving on the stream allows", %{session: session} do
    document = create_document("almanac")

    session
    |> visit(Page1)
    |> click(button("Log in"))
    |> assert_text(css("#result"), "logged_in")
    |> reload()
    |> assert_text(css("#managed_documents"), ~r/^$/)
    |> mark_this_page_load()

    Auth.grant_role(session_user(), :owner, document)

    session
    |> assert_text(css("#managed_documents"), ~r/^almanac$/)
    |> assert_same_page_load()
  end

  feature "hides what a revoke arriving on the stream forbids", %{session: session} do
    document = create_document("bestiary")

    session
    |> visit(Page1)
    |> click(button("Log in"))
    |> assert_text(css("#result"), "logged_in")

    user = session_user()
    Auth.grant_role(user, :owner, document)

    session
    |> reload()
    |> assert_text(css("#managed_documents"), ~r/^bestiary$/)
    |> mark_this_page_load()

    Auth.revoke_role(user, :owner, document)

    session
    |> assert_text(css("#managed_documents"), ~r/^$/)
    |> assert_same_page_load()
  end

  # The document is private, so the user may read it only once the grant is given - and the
  # browser, holding nothing of it, is handed it whole while the stream stays attached. The held
  # documents say it arrived, rather than a check moving on a row the browser already had.
  feature "brings a row a grant given on the stream lets its user read", %{session: session} do
    document =
      %{public: false, title: "grimoire"}
      |> Document.new()
      |> DB.create!()

    session
    |> visit(Page1)
    |> click(button("Log in"))
    |> assert_text(css("#result"), "logged_in")
    |> reload()
    |> await_local_fill()
    |> mark_this_page_load()

    # Only the stream brings it, so it shows only on a render of the browser's own database - which
    # would list the private document beside it if the browser already held that.
    create_document("almanac")

    session
    |> assert_text(css("#held_documents"), ~r/^almanac$/)
    |> assert_text(css("#managed_documents"), ~r/^$/)

    Auth.grant_role(session_user(), :owner, document)

    session
    |> assert_text(css("#held_documents"), ~r/^almanac,grimoire$/)
    |> assert_text(css("#managed_documents"), ~r/^grimoire$/)
    |> assert_same_page_load()
  end

  # A role held on one row says nothing about another - the client evaluates each row against
  # the grants it holds, the way the server does.
  feature "shows only the rows the session user's grants reach", %{session: session} do
    create_document("codex")
    dossier = create_document("dossier")

    session
    |> visit(Page1)
    |> click(button("Log in"))
    |> assert_text(css("#result"), "logged_in")
    |> reload()
    |> mark_this_page_load()

    Auth.grant_role(session_user(), :owner, dossier)

    session
    |> assert_text(css("#managed_documents"), ~r/^dossier$/)
    |> assert_same_page_load()
  end

  feature "shows nothing to a session with no user at all", %{session: session} do
    create_document("ephemeris")

    session
    |> visit(Page1)
    |> assert_text(css("#managed_documents"), ~r/^$/)
  end
end
