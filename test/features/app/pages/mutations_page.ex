defmodule HologramFeatureTests.MutationsPage do
  use Hologram.Page
  use Hologram.Query

  alias HologramFeatureTests.Components.Mutations.Notes
  alias HologramFeatureTests.Entities.User

  route "/mutations"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <p>
      <button $click={command: :log_in}> Log in </button>
    </p>
    <Notes cid="notes" />
    <p>
      Result: <strong id="result"><code>{@result}</code></strong>
    </p>
    """
  end

  def action(:show_result, params, component) do
    put_state(component, :result, params.result)
  end

  def command(:log_in, _params, server) do
    user =
      User
      |> Entity.new(email: "session@example.com")
      |> trust()
      |> DB.create!()

    put_action(%{server | user_id: user.id}, :show_result, result: "logged_in")
  end
end
