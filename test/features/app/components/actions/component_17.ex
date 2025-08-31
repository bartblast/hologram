defmodule HologramFeatureTests.Components.Actions.Component17 do
  use Hologram.Component

  def init(_props, component, _server) do
    put_action(component, name: :delayed_action_11, target: "page", delay: 3_000)
  end

  def template do
    ~HOLO"Component17"
  end
end
