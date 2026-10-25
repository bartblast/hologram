defmodule HologramFeatureTests.Components.LateResultLayout do
  use Hologram.Component
  use Hologram.JS

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  alias Hologram.UI.Runtime
  alias HologramFeatureTests.Components.CommonLayoutStyles

  js_import from: "../../pages/actions/helpers.mjs", as: :helpers

  # Shared by both late result pages, so the layout cid resolves on the destination too, to a new
  # instance of this same module. A result that survives the navigation raises nothing there: it
  # replaces that instance's struct with the left page's, and the destination shows the result.
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

  # Stands in for a slow fetch: the await is still pending after the user has navigated away.
  def action(:slow_layout_action, _params, component) do
    :helpers
    |> JS.call(:slowValue, [3000])
    |> Task.await()

    put_state(component, :result, "layout_result_ran")
  end
end
