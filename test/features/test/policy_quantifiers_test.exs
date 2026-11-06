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
  alias HologramFeatureTests.Policies.Page9

  # A milestone is readable by the members of its project - a rule reading a set, so what a session
  # sees moves with the project's member rows, not with the milestone rows themselves. The member
  # rows are written from the test process: what reaches the screen afterwards came through the
  # stream re-running the window, or through the resume.
  #
  # The browser checks the rules over sets on its own: a milestone's update from the member rows it
  # holds, and a project's delete - while none of its milestones exists - from the milestones it
  # holds, or the server's verdict when it holds none.
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

  defp add_member(project, user, seat) do
    %{project_id: project.id, seat: seat, user_id: user.id}
    |> ProjectMember.new()
    |> DB.create!()
  end

  defp create_empty_project(name) do
    %{name: name}
    |> Project.new()
    |> DB.create!()
  end

  defp create_milestone(project, title) do
    %{project_id: project.id, title: title}
    |> Milestone.new()
    |> DB.create!()
  end

  # A project holding one milestone with the given title.
  defp create_project(title) do
    project = create_empty_project("#{title}_project")
    create_milestone(project, title)

    project
  end

  defp log_in(session, page) do
    session
    |> visit(page)
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

    log_in(session, Page8)
    add_member(joined, session_user(), :viewer)

    session
    |> reload()
    |> assert_text(css("#milestones"), ~r/^alpha$/)
  end

  feature "shows a project's milestones once a membership arrives on the stream", %{
    session: session
  } do
    project = create_project("gamma")

    session
    |> log_in(Page8)
    |> reload()
    |> assert_text(css("#milestones"), ~r/^$/)
    |> mark_this_page_load()

    add_member(project, session_user(), :viewer)

    session
    |> assert_text(css("#milestones"), ~r/^gamma$/)
    |> assert_same_page_load()
  end

  feature "hides a project's milestones once the membership is removed", %{session: session} do
    project = create_project("delta")

    log_in(session, Page8)
    member = add_member(project, session_user(), :viewer)

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
    |> log_in(Page8)
    |> reload()
    |> assert_text(css("#milestones"), ~r/^$/)
    |> mark_this_page_load()

    instance_id = current_instance_id(session)
    :ok = simulate_sse_disconnect(instance_id)

    add_member(project, session_user(), :viewer)

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

    add_member(project, outsider, :viewer)

    session
    |> visit(Page8)
    |> assert_text(css("#result"), "none")
    |> assert_text(css("#milestones"), ~r/^$/)
  end

  feature "shows the edit control to a full-seat member and not to a viewer", %{session: session} do
    full = create_project("eta")
    viewed = create_project("theta")

    log_in(session, Page9)
    user = session_user()
    add_member(full, user, :full)
    add_member(viewed, user, :viewer)

    session
    |> reload()
    |> assert_text(css("#milestones"), ~r/^eta,theta$/)
    |> assert_text(css("#editable_milestones"), ~r/^eta$/)
  end

  feature "takes the edit control away once a seat change arrives on the stream", %{
    session: session
  } do
    project = create_project("iota")

    log_in(session, Page9)
    member = add_member(project, session_user(), :full)

    session
    |> reload()
    |> assert_text(css("#editable_milestones"), ~r/^iota$/)
    |> mark_this_page_load()

    DB.update!(ProjectMember, member.id, seat: :viewer)

    session
    |> assert_text(css("#editable_milestones"), ~r/^$/)
    |> assert_text(css("#milestones"), ~r/^iota$/)
    |> assert_same_page_load()
  end

  feature "takes the delete control away once a milestone arrives on the stream", %{
    session: session
  } do
    project = create_empty_project("kappa")

    log_in(session, Page9)
    add_member(project, session_user(), :viewer)

    session
    |> reload()
    |> assert_text(css("#deletable_projects"), ~r/^kappa$/)
    |> mark_this_page_load()

    create_milestone(project, "lambda")

    session
    |> assert_text(css("#deletable_projects"), ~r/^$/)
    |> assert_text(css("#milestones"), ~r/^lambda$/)
    |> assert_same_page_load()
  end

  feature "takes the delete control away at once when the user adds a milestone", %{
    session: session
  } do
    project = create_empty_project("mu")

    log_in(session, Page9)
    add_member(project, session_user(), :viewer)

    session
    |> reload()
    |> assert_text(css("#deletable_projects"), ~r/^mu$/)
    |> mark_this_page_load()
    |> hold_mutation_requests()
    |> click(button("Add a milestone"))
    |> assert_text(css("#result"), "created_omega")
    |> assert_text(css("#deletable_projects"), ~r/^$/)
    |> assert_text(css("#milestones"), ~r/^omega$/)
    |> assert_same_page_load()

    # Nothing has reached the server while the request is held, so the milestone the browser holds
    # is what answered.
    assert DB.read(Milestone) == []

    session
    |> release_mutations()
    |> await_pending_writes(0)

    assert [%Milestone{title: "omega"}] = DB.read(Milestone)
  end
end
