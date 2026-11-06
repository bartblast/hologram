defmodule HologramFeatureTests.PolicyQuantifiersTest do
  # async: false - each test truncates the shared tables.
  use HologramFeatureTests.TestCase, async: false

  alias Hologram.Auth.RoleGrant
  alias Hologram.DB
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias HologramFeatureTests.Entities.Memo
  alias HologramFeatureTests.Entities.Milestone
  alias HologramFeatureTests.Entities.Note
  alias HologramFeatureTests.Entities.Project
  alias HologramFeatureTests.Entities.ProjectMember
  alias HologramFeatureTests.Entities.User
  alias HologramFeatureTests.Policies.Page8

  # A milestone is readable by the members of its project - a rule reading a set, so what a session
  # sees moves with the project's member rows, not with the milestone rows themselves. The member
  # rows are written from the test process: what reaches the screen afterwards came through the
  # stream re-running the window, or through the resume.
  setup do
    await_evaluator_drain()

    tables =
      Enum.map_join(
        [Memo, Milestone, Note, Project, ProjectMember, RoleGrant, User],
        ", ",
        fn entity_type ->
          ~s("hologram_data"."#{Mapper.table_name(entity_type)}")
        end
      )

    {:ok, _result} = Connection.query("TRUNCATE #{tables}", [])

    :ok
  end

  defp add_member(project, user) do
    %{project_id: project.id, seat: :viewer, user_id: user.id}
    |> ProjectMember.new()
    |> DB.create!()
  end

  # A project holding one milestone with the given title.
  defp create_project(title) do
    project =
      %{name: "#{title}_project"}
      |> Project.new()
      |> DB.create!()

    %{project_id: project.id, title: title}
    |> Milestone.new()
    |> DB.create!()

    project
  end

  defp log_in(session) do
    session
    |> visit(Page8)
    |> click(button("Log in"))
    |> assert_text(css("#result"), "logged_in")
  end

  defp session_user do
    User
    |> DB.read()
    |> Enum.find(&(&1.email == "teammate@example.com"))
  end

  feature "shows a project's milestones to its members only", %{session: session} do
    joined = create_project("alpha")
    create_project("beta")

    log_in(session)
    add_member(joined, session_user())

    session
    |> reload()
    |> assert_text(css("#milestones"), ~r/^alpha$/)
  end

  feature "shows a project's milestones once a membership arrives on the stream", %{
    session: session
  } do
    project = create_project("gamma")

    session
    |> log_in()
    |> reload()
    |> assert_text(css("#milestones"), ~r/^$/)
    |> mark_this_page_load()

    add_member(project, session_user())

    session
    |> assert_text(css("#milestones"), ~r/^gamma$/)
    |> assert_same_page_load()
  end

  feature "hides a project's milestones once the membership is removed", %{session: session} do
    project = create_project("delta")

    log_in(session)
    member = add_member(project, session_user())

    session
    |> reload()
    |> assert_text(css("#milestones"), ~r/^delta$/)
    |> mark_this_page_load()

    DB.delete!(member)

    session
    |> assert_text(css("#milestones"), ~r/^$/)
    |> assert_same_page_load()
  end

  # With the stream killed, the member row written from the test process wakes nothing this browser
  # can hear - the milestone it covers never moved, so only the resume can bring it.
  feature "shows a project's milestones once a membership given while away is caught up on", %{
    session: session
  } do
    project = create_project("epsilon")

    session
    |> log_in()
    |> reload()
    |> assert_text(css("#milestones"), ~r/^$/)
    |> mark_this_page_load()

    instance_id = current_instance_id(session)
    :ok = simulate_sse_disconnect(instance_id)

    add_member(project, session_user())

    # Wallaby's own retry rides out the reconnect backoff, which starts at 250 ms.
    session
    |> assert_text(css("#milestones"), ~r/^epsilon$/)
    |> assert_same_page_load()
  end

  feature "shows a visitor no project's milestones", %{session: session} do
    project = create_project("zeta")

    outsider =
      %{email: "outsider@example.com"}
      |> User.new()
      |> DB.create!()

    add_member(project, outsider)

    session
    |> visit(Page8)
    |> assert_text(css("#result"), "none")
    |> assert_text(css("#milestones"), ~r/^$/)
  end
end
