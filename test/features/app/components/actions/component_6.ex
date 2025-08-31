defmodule HologramFeatureTests.Components.Actions.Component6 do
  use Hologram.Component

  def init(_props, component, _server) do
    put_action(component, :component_6_action)
  end

  def template do
    ~HOLO"Component6 template<br />"
  end

  def action(:component_6_action, _params, component) do
    put_action(component,
      name: :append_result,
      target: "page",
      params: %{action_result: :component_6_action_executed}
    )
  end
end
