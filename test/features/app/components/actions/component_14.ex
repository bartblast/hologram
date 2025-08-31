defmodule HologramFeatureTests.Components.Actions.Component14 do
  use Hologram.Component

  def init(_props, component) do
    put_action(component, :component_14_action)
  end

  def template do
    ~HOLO"Component14 template<br />"
  end

  def action(:component_14_action, _params, component) do
    put_action(component,
      name: :append_result,
      target: "page",
      params: %{action_result: :component_14_action_executed}
    )
  end
end
