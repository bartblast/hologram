defmodule HologramFeatureTests.IdentityChangePage do
  use Hologram.Page
  use Hologram.DB

  alias Hologram.UI.Link
  alias HologramFeatureTests.Components.IdentityChange.Component1
  alias HologramFeatureTests.Entities.User
  alias HologramFeatureTests.IdentityChangeDestinationPage

  route "/identity-change"

  layout HologramFeatureTests.Components.DefaultLayout

  state :result, :string

  def init(_params, component, _server) do
    put_state(component, :result, "none")
  end

  def template do
    ~HOLO"""
    <p>
      <button $click={command: :log_in_as_ann}> Log in as Ann </button>
      <button $click={command: :log_in_as_bob}> Log in as Bob </button>
      <button $click={command: :log_out}> Log out </button>
      <button $click="put_marker"> Put marker </button>
      <Link to={IdentityChangeDestinationPage}>Destination link</Link>
    </p>
    <p>
      Result: <strong id="result"><code>{@result}</code></strong>
    </p>
    <Component1 cid="component_1" />
    """
  end

  # State only the page as it was left holds, so a page that shows it after Back was restored.
  def action(:put_marker, _params, component) do
    put_state(component, :result, "marked")
  end

  def action(:show_result, params, component) do
    put_state(component, :result, params.result)
  end

  def command(:log_in_as_ann, _params, server) do
    log_in(server, "ann@example.com", "logged_in_as_ann")
  end

  def command(:log_in_as_bob, _params, server) do
    log_in(server, "bob@example.com", "logged_in_as_bob")
  end

  def command(:log_out, _params, server) do
    put_action(%{server | user_id: nil}, :show_result, result: "logged_out")
  end

  # The test seeds both users before the visit.
  defp log_in(server, email, result) do
    [user] =
      User
      |> filter(email: ^email)
      |> trust()
      |> DB.read()

    put_action(%{server | user_id: user.id}, :show_result, result: result)
  end
end
