defmodule HologramFeatureTests.Components.Actions.Component9 do
  use Hologram.Component

  def template do
    ~HOLO"Component9 template<br />"
  end

  def action(:component_9_action, _params, component) do
    put_action(component,
      name: :append_result,
      target: "page",
      params: %{action_result: :component_9_action_executed}
    )
  end
end
