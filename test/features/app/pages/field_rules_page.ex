defmodule HologramFeatureTests.FieldRulesPage do
  use Hologram.Page
  use Hologram.DB

  alias HologramFeatureTests.Components.FieldRules.BulletinPanel
  alias HologramFeatureTests.Entities.Bulletin
  alias HologramFeatureTests.Entities.User

  route "/field-rules"

  layout HologramFeatureTests.Components.DefaultLayout

  state :result, :string
  state :session_user_id, :any

  # The session user's id is what the page was mounted under - a reload after "Log in" is what
  # makes it theirs.
  def init(_params, component, server) do
    component
    |> put_state(:result, nil)
    |> put_state(:session_user_id, server.user_id)
  end

  # No label may be a substring of another - Wallaby matches a button by substring.
  def template do
    ~HOLO"""
    <p>
      <button $click="change_title"> Change title </button>
      <button $click="change_topic"> Change topic </button>
      <button $click="check_fields_locally"> Check fields locally </button>
      <button $click={command: :log_in}> Log in </button>
    </p>
    <BulletinPanel cid="bulletin_panel" />
    <p>
      Result: <strong id="result"><code>{@result}</code></strong>
    </p>
    """
  end

  # The writes run in the BROWSER, which applies them at once and sends them in the action's batch.
  # The server judges each by the fields it changes, and a refused one is rolled back in the tab.
  def action(:change_title, _params, component) do
    bulletin()
    |> put_attribute(title: "renamed")
    |> DB.update!()

    put_state(component, :result, "changed_title")
  end

  def action(:change_topic, _params, component) do
    bulletin()
    |> put_attribute(topic: "news")
    |> DB.update!()

    put_state(component, :result, "changed_topic")
  end

  # Asked in the browser, over the row it holds and the rules the build carries.
  def action(:check_fields_locally, _params, component) do
    user_id = component.state.session_user_id
    bulletin = bulletin()

    answers = [
      topic: can?(user_id, {:update, :topic}, bulletin),
      title: can?(user_id, {:update, :title}, bulletin),
      both: can?(user_id, {:update, [:topic, :title]}, bulletin)
    ]

    result = Enum.map_join(answers, ",", fn {field, answer} -> "#{field}:#{answer}" end)

    put_state(component, :result, result)
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

  defp bulletin do
    Bulletin
    |> one()
    |> DB.read()
  end
end
