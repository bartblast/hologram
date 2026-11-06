defmodule HologramFeatureTests.Policies.Page8 do
  use Hologram.Page

  alias Hologram.DB
  alias HologramFeatureTests.Components.Policies.Component9
  alias HologramFeatureTests.Entities.User

  route "/policies/8"

  layout HologramFeatureTests.Components.DefaultLayout

  def template do
    ~HOLO"""
    <p>
      <button $click="log_in"> Log in </button>
    </p>
    <p>
      Result: <strong id="result"><code>{@result}</code></strong>
    </p>
    <Component9 />
    """
  end

  def init(_params, component, _server) do
    put_state(component, :result, "none")
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
