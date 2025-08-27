defmodule HologramFeatureTests.Components.Actions.Component18 do
  use Hologram.Component

  def init(_props, component) do
    put_action(component, name: :delayed_action_12, target: "page", delay: 3_000)
  end

  def template do
    ~HOLO"Component18"
  end
end
