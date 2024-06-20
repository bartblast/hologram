defmodule HologramFeatureTests.Components.ActionsLayout do
  use Hologram.Component
  alias Hologram.UI.Runtime

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <Runtime />
      </head>
      <body style="padding: 25px">
        <p>
          <button id="layout_action_1" $click="layout_action_1"> layout_action_1 </button>
          <button id="component_1_action_3" $click={%Action{name: :component_1_action_3, params: %{a: 1, b: 2}, target: "component_1"}}> component_1_action_3 </button>
        </p>
        <p>
          Layout result: <strong id="layout_result"><code>{inspect(@result)}</code></strong>
        </p>
        <slot />
      </body>
    </html>
    """
  end

  def action(:layout_action_1, params, component) do
    put_state(component, :result, {"layout_action_1", params})
  end

  def action(:layout_action_2, params, component) do
    put_state(component, :result, {"layout_action_2", params})
  end
end
