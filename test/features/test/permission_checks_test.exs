defmodule HologramFeatureTests.PermissionChecksTest do
  # async: false - each test truncates the shared tables.
  use HologramFeatureTests.TestCase, async: false

  alias Hologram.Auth
  alias Hologram.Auth.RoleGrant
  alias Hologram.DB
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias HologramFeatureTests.Entities.Document
  alias HologramFeatureTests.Entities.Note
  alias HologramFeatureTests.Entities.User
  alias HologramFeatureTests.Policies.Page1

  # The other end of the permission check: the policies tests assert what the SERVER answers,
  # and these assert that the CLIENT answers the same - from the rules its build carries and the
  # grant rows its pot holds. Nothing here reloads: a grant is written from the test process, the
  # stream delivers the row, and the gated UI follows.
  setup do
    await_evaluator_drain()

    tables =
      Enum.map_join([Document, Note, RoleGrant, User], ", ", fn entity_type ->
        ~s("hologram_data"."#{Mapper.table_name(entity_type)}")
      end)

    {:ok, _result} = Connection.query("TRUNCATE #{tables}", [])

    :ok
  end

  # Proves the DOM changed without the page being fetched again - a reload would take this
  # marker with it, so a passing assertion after one would say nothing.
  defp mark_this_page_load(session) do
    execute_script(session, "globalThis.__thisPageLoad = 'held';")
  end

  defp assert_same_page_load(session) do
    assert_script_result(session, "return globalThis.__thisPageLoad;", "held")
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

    Auth.grant_role(session_user(), document, :owner)

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
    Auth.grant_role(user, document, :owner)

    session
    |> reload()
    |> assert_text(css("#managed_documents"), ~r/^bestiary$/)
    |> mark_this_page_load()

    Auth.revoke_role(user, document, :owner)

    session
    |> assert_text(css("#managed_documents"), ~r/^$/)
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

    Auth.grant_role(session_user(), dossier, :owner)

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
