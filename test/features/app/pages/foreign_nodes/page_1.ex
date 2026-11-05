defmodule HologramFeatureTests.ForeignNodes.Page1 do
  use Hologram.Page

  alias Hologram.UI.Link
  alias HologramFeatureTests.ForeignNodes.Page2

  route "/foreign-nodes/1"

  layout HologramFeatureTests.Components.ForeignNodesLayout

  def init(_params, component, _server) do
    put_state(component, :theme, "light")
  end

  # The root sits directly in the body, and its class comes from state, so a snapshot restored over
  # the served state changes an attribute of a direct child of the body.
  def template do
    ~HOLO"""
    <div id="page-1-root" class={@theme}>
      <h1>Foreign nodes page 1</h1>
      <button $click="switch_to_dark_theme">Switch to dark theme</button>
      <Link to={Page2}>Page 2 link</Link>
    </div>
    """
  end

  def action(:switch_to_dark_theme, _params, component) do
    put_state(component, :theme, "dark")
  end
end
