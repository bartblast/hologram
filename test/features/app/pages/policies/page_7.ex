defmodule HologramFeatureTests.Policies.Page7 do
  use Hologram.Page
  use Hologram.DB

  alias HologramFeatureTests.Components.Policies.Component8
  alias HologramFeatureTests.Entities.User

  route "/policies/7"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, "none")
  end

  def template do
    ~HOLO"""
    <p>
      <button $click={command: :log_in}> Log in </button>
    </p>
    <p>
      Result: <strong id="result"><code>{@result}</code></strong>
    </p>
    <Component8 cid="component_8" />
    """
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
end
