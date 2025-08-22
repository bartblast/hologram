defmodule HologramFeatureTests.Components.Actions.Component5 do
  use Hologram.Component

  def init(_props, component, _server) do
    put_action(component, :component_5_action)
  end

  def template do
    ~HOLO"Component5 template<br />"
  end

  def action(:component_5_action, _params, component) do
    put_action(component,
      name: :append_result,
      target: "page",
      params: %{action_result: :component_5_action_executed}
    )
  end
end
