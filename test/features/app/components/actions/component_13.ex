defmodule HologramFeatureTests.Components.Actions.Component13 do
  use Hologram.Component

  def init(_props, component) do
    put_action(component, :component_13_action)
  end

  def template do
    ~HOLO"Component13 template<br />"
  end

  def action(:component_13_action, _params, component) do
    put_action(component,
      name: :append_result,
      target: "page",
      params: %{action_result: :component_13_action_executed}
    )
  end
end
