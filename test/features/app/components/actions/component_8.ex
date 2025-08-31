defmodule HologramFeatureTests.Components.Actions.Component8 do
  use Hologram.Component

  def init(_props, component, _server) do
    put_action(component, name: :component_9_action, target: "ccc_component")
  end

  def template do
    ~HOLO"Component8 template<br />"
  end
end
