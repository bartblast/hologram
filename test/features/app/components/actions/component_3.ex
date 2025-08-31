defmodule HologramFeatureTests.Components.Actions.Component3 do
  use Hologram.Component
  alias HologramFeatureTests.Components.Actions.Component4

  def init(_params, component, _server) do
    put_action(component,
      name: :component_4_action,
      target: "component_4",
      params: %{queued_from: "component_3"}
    )
  end

  def template do
    ~HOLO"""
    <Component4 cid="component_4" />
    """
  end
end
