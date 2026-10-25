defmodule HologramFeatureTests.RoleChecksTest do
  # async: false - each test truncates the shared tables.
  use HologramFeatureTests.TestCase, async: false

  alias Hologram.Auth
  alias Hologram.Auth.RoleGrant
  alias Hologram.DB
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias HologramFeatureTests.Entities.Document
  alias HologramFeatureTests.Entities.Memo
  alias HologramFeatureTests.Entities.Note
  alias HologramFeatureTests.Entities.User
  alias HologramFeatureTests.Policies.Page4
  alias HologramFeatureTests.Roles.Admin

  # The checks answer in the browser, from the grant rows it holds and the roles its build carries.
  # Each feature changes a grant only once the page is loaded and the browser holds its rows, and
  # asserts on the same page load - so what is on screen is the browser's answer, not the server's
  # render.
  #
  # The tables truncate in one statement: the memo, note and role grant tables' foreign keys to the
  # user table make Postgres reject truncating the referenced table alone.
  setup do
    await_evaluator_drain()

    tables =
      Enum.map_join([Document, Memo, Note, RoleGrant, User], ", ", fn entity_type ->
        ~s("hologram_data"."#{Mapper.table_name(entity_type)}")
      end)

    {:ok, _result} = Connection.query("TRUNCATE #{tables}", [])

    :ok
  end

  defp create_document(title) do
    %{public: true, title: title}
    |> Document.new()
    |> DB.create!()
  end

  defp grants(user_id) do
    RoleGrant
    |> DB.read()
    |> Enum.filter(&(&1.user_id == user_id))
    |> Enum.map(& &1.role)
    |> Enum.sort()
  end

  defp session_user do
    User
    |> DB.read()
    |> Enum.find(&(&1.email == "member@example.com"))
  end

  # A command changes the session and not the page already mounted, so the page is loaded again
  # before it knows who is signed in. It is marked once the browser holds its rows, so a grant
  # written after this reaches the browser on the stream rather than with the page.
  defp sign_in(session) do
    session
    |> visit(Page4)
    |> click(button("Log in"))
    |> assert_text(css("#result"), "logged_in")
    |> reload()
    |> await_local_fill()
    |> mark_this_page_load()
  end

  # Owner extends editor, so the row held as owner is listed as an editor's too.
  feature "shows the roles an extending role reaches on each row", %{session: session} do
    almanac = create_document("almanac")
    bestiary = create_document("bestiary")

    session
    |> sign_in()
    |> assert_text(css("#documents"), ~r/^almanac,bestiary$/)
    |> assert_text(css("#editor_documents"), ~r/^$/)

    Auth.grant_role(session_user(), :editor, almanac)
    Auth.grant_role(session_user(), :owner, bestiary)

    session
    |> assert_text(css("#editor_documents"), ~r/^almanac,bestiary$/)
    |> assert_text(css("#owner_documents"), ~r/^bestiary$/)
    |> assert_same_page_load()
  end

  feature "counts a role held on the whole entity type for every row", %{session: session} do
    create_document("chronicle")
    create_document("compendium")

    session
    |> sign_in()
    |> assert_text(css("#documents"), ~r/^chronicle,compendium$/)
    |> assert_text(css("#editor_documents"), ~r/^$/)

    Auth.grant_role(session_user(), :editor, Document)

    session
    |> assert_text(css("#editor_documents"), ~r/^chronicle,compendium$/)
    |> assert_text(css("#owner_documents"), ~r/^$/)
    |> assert_same_page_load()
  end

  feature "hides a role revoked on the stream", %{session: session} do
    dossier = create_document("dossier")

    session
    |> visit(Page4)
    |> click(button("Log in"))
    |> assert_text(css("#result"), "logged_in")

    Auth.grant_role(session_user(), :owner, dossier)

    session
    |> reload()
    |> await_local_fill()
    |> mark_this_page_load()
    |> assert_text(css("#owner_documents"), ~r/^dossier$/)
    |> assert_text(css("#editor_documents"), ~r/^dossier$/)

    Auth.revoke_role(session_user(), :owner, dossier)

    session
    |> assert_text(css("#owner_documents"), ~r/^$/)
    |> assert_text(css("#editor_documents"), ~r/^$/)
    |> assert_same_page_load()
  end

  # The revocation runs in the browser and its request is held: the check answers from the
  # browser's own rows while the server still holds the grant.
  feature "hides a role the browser revoked itself before the server answers", %{
    session: session
  } do
    ledger = create_document("ledger")

    session
    |> visit(Page4)
    |> click(button("Log in"))
    |> assert_text(css("#result"), "logged_in")

    Auth.grant_role(session_user(), :editor, ledger)

    session
    |> reload()
    |> await_local_fill()
    |> mark_this_page_load()
    |> assert_text(css("#editor_documents"), ~r/^ledger$/)
    |> hold_mutation_requests()
    |> click(button("Leave"))
    |> assert_text(css("#result"), "left")
    |> assert_text(css("#editor_documents"), ~r/^$/)
    |> assert_same_page_load()

    assert grants(session_user().id) == [:editor]

    session
    |> release_mutations()
    |> await_pending_writes(0)

    assert grants(session_user().id) == []
  end

  feature "shows a global role granted on the stream", %{session: session} do
    session
    |> sign_in()
    |> assert_text(css("#admin"), "false")

    Auth.grant_role(session_user(), Admin)

    session
    |> assert_text(css("#admin"), "true")
    |> assert_same_page_load()
  end

  # The page the server sent is read as well: the browser renders the checks again from its own
  # rows once they land, so the two answers are asserted apart.
  feature "shows no role to a session with no user at all", %{session: session} do
    create_document("ephemeris")

    %HTTPoison.Response{body: html} = HTTPoison.get!("http://localhost:4002/policies/4")

    assert html =~ ~r{<strong id="documents"><code>ephemeris</code></strong>}
    assert html =~ ~r{<strong id="admin"><code>false</code></strong>}
    assert html =~ ~r{<strong id="editor_documents"><code></code></strong>}

    session
    |> visit(Page4)
    |> await_local_fill()
    |> assert_text(css("#documents"), ~r/^ephemeris$/)
    |> assert_text(css("#admin"), "false")
    |> assert_text(css("#editor_documents"), ~r/^$/)
    |> assert_text(css("#owner_documents"), ~r/^$/)
  end
end
