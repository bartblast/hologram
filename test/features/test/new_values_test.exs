defmodule HologramFeatureTests.NewValuesTest do
  use HologramFeatureTests.TestCase, async: false

  alias Hologram.Auth
  alias Hologram.Auth.RoleGrant
  alias Hologram.DB
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias HologramFeatureTests.Entities.Errand
  alias HologramFeatureTests.Entities.Memo
  alias HologramFeatureTests.Entities.Note
  alias HologramFeatureTests.Entities.ProjectMember
  alias HologramFeatureTests.Entities.Squad
  alias HologramFeatureTests.Entities.User
  alias HologramFeatureTests.NewValuesPage

  # All the tables truncate in one statement: the memo, note, project member and role grant tables'
  # foreign keys to the user table make Postgres reject truncating the referenced table alone.
  setup do
    tables =
      Enum.map_join([Errand, Memo, Note, ProjectMember, RoleGrant, Squad, User], ", ", fn type ->
        ~s("hologram_data"."#{Mapper.table_name(type)}")
      end)

    {:ok, _result} = Connection.query("TRUNCATE #{tables}", [])

    [start, joined, other] = Enum.map(~w(start joined other), &create_squad/1)

    {:ok, joined: joined, other: other, start: start}
  end

  defp create_errand(squad) do
    %{squad_id: squad.id, title: "the errand"}
    |> Errand.new()
    |> DB.create!()
  end

  defp create_squad(name) do
    %{name: name}
    |> Squad.new()
    |> DB.create!()
  end

  defp refusal(field) do
    ~r/^not allowed to update HologramFeatureTests\.Entities\.Errand "[^"]+" - no allow line that holds covers :#{field}$/
  end

  defp session_user do
    User
    |> DB.read()
    |> Enum.find(&(&1.email == "session@example.com"))
  end

  # A command changes the session and not the page already mounted, so the reload is what makes the
  # page hold the signed-in user. The result reads "none" only on the reloaded page, and the fill
  # is what brings that user's grants, which the render doesn't carry.
  defp sign_in(session, squads) do
    session
    |> visit(NewValuesPage)
    |> click(button("Log in"))
    |> assert_text(css("#result"), "logged_in")

    user = session_user()

    Enum.each(squads, &Auth.grant_role(user, :member, &1))

    session
    |> mark_document()
    |> reload()
    |> wait_for_unmarked_document()
    |> assert_page(NewValuesPage)
    |> assert_text(css("#result"), "none")
    |> assert_text(css("#errands"), "the errand")
    |> assert_text(css("#squads"), "joined")
    |> await_local_fill()
  end

  defp stored_errand do
    [errand] = DB.read(Errand)

    errand
  end

  feature "approves an errand when its rule allows the new value", %{
    session: session,
    start: start
  } do
    create_errand(start)

    session
    |> sign_in([start])
    |> click(button("Approve the errand"))
    |> assert_text(css("#result"), "approved_ok")
    |> assert_text(css("#errands"), "the errand approved")
    |> await_pending_writes(0)

    assert stored_errand().status == :approved
  end

  feature "refuses in the browser a value the rule can never allow", %{
    session: session,
    start: start
  } do
    create_errand(start)

    session
    |> sign_in([start])
    |> hold_mutation_requests()
    |> click(button("Reject the errand"))
    |> assert_text(css("#result"), refusal(:status))
    |> assert_text(css("#errands"), "the errand pending")
    |> await_pending_writes(0)
    |> release_mutations()

    assert stored_errand().status == :pending
  end

  feature "lets an errand be archived and refuses restoring it in the browser", %{
    session: session,
    start: start
  } do
    create_errand(start)

    session
    |> sign_in([start])
    |> click(button("Archive the errand"))
    |> assert_text(css("#result"), "archived_ok")
    |> await_pending_writes(0)
    |> click(button("Restore the errand"))
    |> assert_text(css("#result"), refusal(:archived))
    |> assert_text(css("#errands"), "archived=true")
    |> await_pending_writes(0)

    assert stored_errand().archived == true
  end

  feature "moves an errand to a squad the user is a member of", %{
    joined: joined,
    session: session,
    start: start
  } do
    create_errand(start)

    session
    |> sign_in([start, joined])
    |> click(button("Move to joined squad"))
    |> assert_text(css("#result"), "moved_joined_ok")
    |> assert_text(css("#errands"), "squad=#{joined.id}")
    |> await_pending_writes(0)

    assert stored_errand().squad_id == joined.id
  end

  # Held, so the tab shows the move applied before the server's refusal takes it back.
  feature "leaves a role to the server, which refuses a move to a squad the user isn't in", %{
    joined: joined,
    other: other,
    session: session,
    start: start
  } do
    create_errand(start)

    session =
      session
      |> sign_in([start, joined])
      |> hold_mutation_requests()
      |> click(button("Move to other squad"))
      |> assert_text(css("#result"), "moved_other_ok")
      |> assert_text(css("#errands"), "squad=#{other.id}")

    assert stored_errand().squad_id == start.id

    release_mutations(session)

    assert [%{"reason" => reason, "seq" => 1, "write" => 0}] = await_rejected_writes(session)
    assert reason =~ "no allow line that holds covers :squad"

    assert_text(session, css("#errands"), "squad=#{start.id}")

    assert stored_errand().squad_id == start.id
  end

  feature "needs the role on the squad the errand leaves as well as the one it joins", %{
    joined: joined,
    session: session,
    start: start
  } do
    create_errand(start)

    session =
      session
      |> sign_in([joined])
      |> click(button("Ask about moving to joined"))
      |> assert_text(css("#result"), "move_joined_false")
      |> hold_mutation_requests()
      |> click(button("Move to joined squad"))
      |> assert_text(css("#result"), "moved_joined_ok")
      |> assert_text(css("#errands"), "squad=#{joined.id}")

    release_mutations(session)

    assert [%{"reason" => reason, "seq" => 1, "write" => 0}] = await_rejected_writes(session)
    assert reason =~ "no allow line that holds covers :squad"

    assert_text(session, css("#errands"), "squad=#{start.id}")

    assert stored_errand().squad_id == start.id
  end

  feature "answers can? for one specific change", %{
    joined: joined,
    session: session,
    start: start
  } do
    create_errand(start)

    session
    |> sign_in([start, joined])
    |> click(button("Ask about approving"))
    |> assert_text(css("#result"), "approve_true")
    |> click(button("Ask about rejecting"))
    |> assert_text(css("#result"), "reject_false")
    |> click(button("Ask about moving to joined"))
    |> assert_text(css("#result"), "move_joined_true")
    |> click(button("Ask about moving to other"))
    |> assert_text(css("#result"), "move_other_false")
  end
end
