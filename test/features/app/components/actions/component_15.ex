defmodule HologramFeatureTests.Components.Actions.Component15 do
  use Hologram.Component

  def init(_props, component) do
    put_action(component, name: :component_16_action, target: "ccc_component")
  end

  def template do
    ~HOLO"Component15 template<br />"
  end
end
