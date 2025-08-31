defmodule HologramFeatureTests.Components.Actions.Component16 do
  use Hologram.Component

  def init(_props, component) do
    component
  end

  def template do
    ~HOLO"Component16 template<br />"
  end

  def action(:component_16_action, _params, component) do
    put_action(component,
      name: :append_result,
      target: "page",
      params: %{action_result: :component_16_action_executed}
    )
  end
end
