defmodule HologramFeatureTests.Components.Actions.Component12 do
  use Hologram.Component

  def init(_props, component) do
    put_action(component, :component_12_action)
  end

  def template do
    ~HOLO"Component12 template<br />"
  end

  def action(:component_12_action, _params, component) do
    put_action(component,
      name: :append_result,
      target: "page",
      params: %{action_result: :component_12_action_executed}
    )
  end
end
