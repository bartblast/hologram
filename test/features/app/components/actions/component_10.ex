defmodule HologramFeatureTests.Components.Actions.Component10 do
  use Hologram.Component

  def init(_props, component) do
    put_action(component,
      name: :page_action,
      target: "page",
      params: %{queued_from: "component_10"}
    )
  end

  def template do
    ~HOLO"""
    Component10 template
    """
  end
end
