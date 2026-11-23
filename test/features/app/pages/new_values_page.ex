defmodule HologramFeatureTests.NewValuesPage do
  use Hologram.Page
  use Hologram.DB

  alias Hologram.AccessDeniedError
  alias HologramFeatureTests.Components.NewValues.Errands
  alias HologramFeatureTests.Entities.Errand
  alias HologramFeatureTests.Entities.Squad
  alias HologramFeatureTests.Entities.User

  route "/new-values"

  layout HologramFeatureTests.Components.DefaultLayout

  state :joined_squad_id, :any
  state :other_squad_id, :any
  state :result, :string
  state :session_user_id, :any

  # The squads are seeded by the test before the visit, and read here as trusted code so the page
  # holds their ids whoever is signed in.
  def init(_params, component, server) do
    squads =
      Squad
      |> trust()
      |> DB.read()

    component
    |> put_state(:joined_squad_id, squad_id(squads, "joined"))
    |> put_state(:other_squad_id, squad_id(squads, "other"))
    |> put_state(:result, "none")
    |> put_state(:session_user_id, server.user_id)
  end

  # No label may be a substring of another, since the browser driver matches a button by substring.
  def template do
    ~HOLO"""
    <p>
      <button $click="approve"> Approve the errand </button>
      <button $click="archive"> Archive the errand </button>
      <button $click="ask_approve"> Ask about approving </button>
      <button $click="ask_move_joined"> Ask about moving to joined </button>
      <button $click="ask_move_other"> Ask about moving to other </button>
      <button $click="ask_reject"> Ask about rejecting </button>
      <button $click={command: :log_in}> Log in </button>
      <button $click="move_joined"> Move to joined squad </button>
      <button $click="move_other"> Move to other squad </button>
      <button $click="reject"> Reject the errand </button>
      <button $click="restore"> Restore the errand </button>
    </p>
    <Errands cid="errands" />
    <p>
      Result: <strong id="result"><code>{@result}</code></strong>
    </p>
    """
  end

  # Every write and question here runs in the browser. A refusal the values alone prove is raised
  # here, and one that depends on roles comes back from the server as a rejected batch.
  def action(:approve, _params, component) do
    write(component, "approved", status: :approved)
  end

  def action(:archive, _params, component) do
    write(component, "archived", archived: true)
  end

  def action(:ask_approve, _params, component) do
    ask(component, "approve", status: :approved)
  end

  def action(:ask_move_joined, _params, component) do
    ask(component, "move_joined", squad_id: component.state.joined_squad_id)
  end

  def action(:ask_move_other, _params, component) do
    ask(component, "move_other", squad_id: component.state.other_squad_id)
  end

  def action(:ask_reject, _params, component) do
    ask(component, "reject", status: :rejected)
  end

  def action(:move_joined, _params, component) do
    write(component, "moved_joined", squad_id: component.state.joined_squad_id)
  end

  def action(:move_other, _params, component) do
    write(component, "moved_other", squad_id: component.state.other_squad_id)
  end

  def action(:reject, _params, component) do
    write(component, "rejected", status: :rejected)
  end

  def action(:restore, _params, component) do
    write(component, "restored", archived: false)
  end

  def action(:show_result, params, component) do
    put_state(component, :result, params.result)
  end

  def command(:log_in, _params, server) do
    user =
      %{email: "session@example.com"}
      |> User.new()
      |> trust()
      |> DB.create!()

    put_action(%{server | user_id: user.id}, :show_result, result: "logged_in")
  end

  defp ask(component, name, change) do
    allowed = can?(component.state.session_user_id, :update, errand(), change)

    put_state(component, :result, "#{name}_#{allowed}")
  end

  defp errand do
    Errand
    |> filter(title: "the errand")
    |> one()
    |> DB.read()
  end

  defp squad_id(squads, name) do
    Enum.find(squads, &(&1.name == name)).id
  end

  defp write(component, name, change) do
    result =
      try do
        errand()
        |> put_attribute(change)
        |> DB.update!()

        "#{name}_ok"
      rescue
        error in AccessDeniedError -> error.message
      end

    put_state(component, :result, result)
  end
end
