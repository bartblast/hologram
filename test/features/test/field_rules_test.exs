defmodule HologramFeatureTests.FieldRulesTest do
  use HologramFeatureTests.TestCase, async: false

  alias Hologram.Auth
  alias Hologram.Auth.RoleGrant
  alias Hologram.DB
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias HologramFeatureTests.Entities.Bulletin
  alias HologramFeatureTests.Entities.Memo
  alias HologramFeatureTests.Entities.Note
  alias HologramFeatureTests.Entities.ProjectMember
  alias HologramFeatureTests.Entities.User
  alias HologramFeatureTests.FieldRulesPage

  # All the tables truncate in one statement: the memo, note, project member and role grant tables'
  # foreign keys to the user table make Postgres reject truncating the referenced table alone.
  setup do
    await_evaluator_drain()

    tables =
      Enum.map_join(
        [Bulletin, Memo, Note, ProjectMember, RoleGrant, User],
        ", ",
        fn entity_type ->
          ~s("hologram_data"."#{Mapper.table_name(entity_type)}")
        end
      )

    {:ok, _result} = Connection.query("TRUNCATE #{tables}", [])

    bulletin =
      %{title: "original", topic: "general"}
      |> Bulletin.new()
      |> DB.create!()

    {:ok, bulletin: bulletin}
  end

  # Polls the SERVER until the bulletin's field holds the given value - a browser write lands after
  # its batch's round trip.
  defp await_stored(field, value) do
    Enum.reduce_while(1..100, nil, fn _attempt, _acc ->
      case DB.read(Bulletin) do
        [%Bulletin{} = bulletin] when :erlang.map_get(field, bulletin) == value ->
          {:halt, bulletin}

        _not_yet ->
          Process.sleep(50)
          {:cont, nil}
      end
    end)
  end

  defp session_user do
    User
    |> DB.read()
    |> Enum.find(&(&1.email == "session@example.com"))
  end

  # Signs the session in and gives its user the given role on the bulletin as trusted code, then
  # reloads: the reload is what makes the page hold the session user and the bulletin it may read.
  defp sign_in_as(session, bulletin, role) do
    session
    |> visit(FieldRulesPage)
    |> click(button("Log in"))
    |> assert_text(css("#result"), "logged_in")

    Auth.grant_role(session_user(), role, bulletin)

    session
    |> reload()
    |> assert_page(FieldRulesPage)
    |> assert_text(css("#title"), "original")
    |> await_local_fill()
  end

  feature "lands a member's browser write to a field a line lets them change", %{
    session: session,
    bulletin: bulletin
  } do
    session =
      session
      |> sign_in_as(bulletin, :member)
      |> click(button("Change topic"))
      |> assert_text(css("#result"), "changed_topic")
      |> assert_text(css("#topic"), "news")

    assert %Bulletin{topic: "news"} = await_stored(:topic, "news")

    # The server's answer lands without taking the value back.
    session
    |> await_pending_writes(0)
    |> assert_text(css("#topic"), "news")

    assert script_result(session, "return globalThis.Hologram.writes.rejected();") == []
  end

  feature "rolls back a member's browser write to a field no line lets them change", %{
    session: session,
    bulletin: bulletin
  } do
    # Held, so the tab shows the write applied before the server's refusal takes it back.
    session =
      session
      |> sign_in_as(bulletin, :member)
      |> hold_mutation_requests()
      |> click(button("Change title"))
      |> assert_text(css("#result"), "changed_title")
      |> assert_text(css("#title"), "renamed")

    assert [%Bulletin{title: "original"}] = DB.read(Bulletin)

    release_mutations(session)

    assert [%{"reason" => reason, "seq" => 1, "write" => 0}] = await_rejected_writes(session)
    assert reason =~ "no allow line that holds covers :title"

    assert_text(session, css("#title"), "original")

    assert [%Bulletin{title: "original"}] = DB.read(Bulletin)
  end

  feature "hides a control can? refuses from a member", %{session: session, bulletin: bulletin} do
    session
    |> sign_in_as(bulletin, :member)
    |> refute_has(button("Rename bulletin"))
  end

  feature "shows a control can? grants to an owner, and lands the write it makes", %{
    session: session,
    bulletin: bulletin
  } do
    session
    |> sign_in_as(bulletin, :owner)
    |> click(button("Rename bulletin"))
    |> assert_text(css("#result"), "changed_title")
    |> assert_text(css("#title"), "renamed")

    assert %Bulletin{title: "renamed"} = await_stored(:title, "renamed")
  end

  feature "answers in the browser which fields a member may change", %{
    session: session,
    bulletin: bulletin
  } do
    session
    |> sign_in_as(bulletin, :member)
    |> click(button("Check fields locally"))
    |> assert_text(css("#result"), "topic:true,title:false,both:false")
  end

  feature "answers in the browser which fields an owner may change", %{
    session: session,
    bulletin: bulletin
  } do
    session
    |> sign_in_as(bulletin, :owner)
    |> click(button("Check fields locally"))
    |> assert_text(css("#result"), "topic:true,title:true,both:true")
  end
end
