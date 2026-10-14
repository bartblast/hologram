defmodule HologramFeatureTests.Components.Actions.Component23 do
  use Hologram.Component

  alias HologramFeatureTests.Components.Actions.Component24

  # The owner of the committed value: the editor below shows it, and forwards each commit here.
  def init(_props, component, _server) do
    put_state(component, :value, "ORIGINAL")
  end

  def template do
    ~HOLO"""
    <Component24 cid="component_24" value={@value} />
    """
  end

  def action(:component_23_commit, params, component) do
    put_state(component, :value, params.value)
  end
end
