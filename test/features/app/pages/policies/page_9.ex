defmodule HologramFeatureTests.Policies.Page9 do
  use Hologram.Page
  use Hologram.DB

  alias HologramFeatureTests.Components.Policies.Component10
  alias HologramFeatureTests.Entities.Milestone
  alias HologramFeatureTests.Entities.Project
  alias HologramFeatureTests.Entities.User

  route "/policies/9"

  layout HologramFeatureTests.Components.DefaultLayout

  state :project_id, :any
  state :result, :string

  # The project is seeded by the test before the visit, and read here as trusted code so the page
  # holds its id whoever is signed in.
  def init(_params, component, _server) do
    project =
      Project
      |> trust()
      |> DB.read()
      |> List.first()

    component
    |> put_state(:project_id, project.id)
    |> put_state(:result, "none")
  end

  def template do
    ~HOLO"""
    <p>
      <button $click="add_milestone"> Add a milestone </button>
      <button $click="log_in"> Log in </button>
    </p>
    <p>
      Result: <strong id="result"><code>{@result}</code></strong>
    </p>
    <Component10 />
    """
  end

  # Runs in the browser: the milestone is on the page, and in the project's milestones, before
  # anything has been sent.
  def action(:add_milestone, _params, component) do
    {:ok, milestone} =
      %{project_id: component.state.project_id, title: "omega"}
      |> Milestone.new()
      |> DB.create()

    put_state(component, :result, "created_#{milestone.title}")
  end

  def action(:log_in, _params, component) do
    put_command(component, :log_in)
  end

  def action(:show_result, params, component) do
    put_state(component, :result, params.result)
  end

  def command(:log_in, _params, server) do
    user =
      %{email: "teammate@example.com"}
      |> User.new()
      |> DB.create!()

    put_action(%{server | user_id: user.id}, :show_result, result: "logged_in")
  end
end
