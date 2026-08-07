defmodule HologramFeatureTests.Components.ThrottleLayout do
  use Hologram.Component

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  alias Hologram.UI.Runtime
  alias HologramFeatureTests.Components.CommonLayoutStyles

  def init(_params, component, _server) do
    put_state(component, :result, 0)
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
        <div
          $mouse_move.throttle(2000)="record_mouse_moved"
          id="hover_zone"
          style="width: 100px; height: 100px; background-color: lightgray;">
          <div
            id="hover_zone_inner"
            style="width: 20px; height: 20px; background-color: gray;">
          </div>
        </div>
        <p>
          Layout result: <strong id="layout_result"><code>{inspect(@result)}</code></strong>
        </p>
        <slot />
      </body>
    </html>
    """
  end

  def action(:record_mouse_moved, _params, component) do
    put_state(component, :result, component.state.result + 1)
  end
end
