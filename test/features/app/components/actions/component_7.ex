defmodule HologramFeatureTests.Components.Actions.Component7 do
  use Hologram.Component

  def init(_props, component, _server) do
    put_action(component, :component_7_action)
  end

  def template do
    ~HOLO"Component7 template<br />"
  end

  def action(:component_7_action, _params, component) do
    put_action(component,
      name: :append_result,
      target: "page",
      params: %{action_result: :component_7_action_executed}
    )
  end
end
