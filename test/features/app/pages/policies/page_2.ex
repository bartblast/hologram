defmodule HologramFeatureTests.Policies.Page2 do
  use Hologram.Page
  use Hologram.DB

  alias HologramFeatureTests.Components.Policies.Component3
  alias HologramFeatureTests.Entities.Memo
  alias HologramFeatureTests.Entities.User

  route "/policies/2"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, "none")
  end

  def template do
    ~HOLO"""
    <p>
      <button $click="log_in"> Log in </button>
      <button $click="write_own_memo"> Write own memo </button>
    </p>
    <p>
      Result: <strong id="result"><code>{@result}</code></strong>
    </p>
    <Component3 cid="component_3" />
    """
  end

  def action(:log_in, _params, component) do
    put_command(component, :log_in)
  end

  def action(:show_result, params, component) do
    put_state(component, :result, params.result)
  end

  def action(:write_own_memo, _params, component) do
    put_command(component, :write_own_memo)
  end

  def command(:log_in, _params, server) do
    user =
      %{email: "owner@example.com"}
      |> User.new()
      |> trust()
      |> DB.create!()

    put_action(%{server | user_id: user.id}, :show_result, result: "logged_in")
  end

  # Pinned, so only the alternative naming its author lets the session user pin it.
  def command(:write_own_memo, _params, server) do
    %{author_id: server.user_id, body: "own_memo", pinned: true}
    |> Memo.new()
    |> trust()
    |> DB.create!()

    put_action(server, :show_result, result: "wrote_own_memo")
  end
end
