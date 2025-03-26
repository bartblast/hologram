defmodule HologramFeatureTests.Components.ActionsLayout do
  use Hologram.Component

  alias Hologram.UI.Runtime
  alias HologramFeatureTests.Components.CommonLayoutStyles

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <Runtime />
        <CommonLayoutStyles />
      </head>
      <body>
        <p>
          <button id="layout_action_1" $click="layout_action_1"> layout_action_1 </button>
          <button id="page_action_6" $click={action: :page_action_6, target: "page", params: %{a: 1, b: 2}}> page_action_6 </button>
          <button id="component_1_action_3" $click={action: :component_1_action_3, target: "component_1", params: %{a: 1, b: 2}}> component_1_action_3 </button>
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

  def action(:layout_action_3, params, component) do
    put_state(component, :result, {"layout_action_3", params})
  end
end
