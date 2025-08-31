defmodule HologramFeatureTests.Components.LayoutWithQueuedAction do
  use Hologram.Component

  alias Hologram.UI.Runtime
  alias HologramFeatureTests.Components.CommonLayoutStyles

  def init(_props, component, _server) do
    put_action(component, :layout_action)
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
        <slot />
      </body>
    </html>
    """
  end

  def action(:layout_action, _params, component) do
    put_action(component,
      name: :append_result,
      target: "page",
      params: %{action_result: :layout_action_executed}
    )
  end
end
