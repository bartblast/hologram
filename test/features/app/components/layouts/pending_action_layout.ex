defmodule HologramFeatureTests.Components.PendingActionLayout do
  use Hologram.Component

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  alias Hologram.UI.Runtime
  alias HologramFeatureTests.Components.CommonLayoutStyles

  # The shell every page in this layout shares. Its cid is the same string on every page, so it is
  # what a dispatch aimed at the layout still resolves to after a navigation.
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
          Layout result: <strong id="layout_result"><code>{inspect(@result)}</code></strong>
        </p>
        <slot />
      </body>
    </html>
    """
  end

  def action(:record_layout_action, _params, component) do
    put_state(component, :result, "layout_action_ran")
  end
end
