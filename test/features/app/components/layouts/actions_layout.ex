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
        <slot />
        <p>
          <button id="layout_action_1" $click="layout_action_1"> layout_action_1 </button>
        </p>        
        <p>
          Layout result: <strong id="layout_result">{inspect(@result)}</strong>
        </p>         
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
