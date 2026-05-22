defmodule HologramFeatureTests.Components.RealtimeLayout do
  use Hologram.Component

  alias Hologram.UI.Runtime

  def init(_props, component, server) do
    {
      put_state(component, :received, "none"),
      put_subscription(server, {:room, 9})
    }
  end

  def template do
    ~HOLO"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <Runtime />
      </head>
      <body>
        <p>Channel 9: <strong id="received-shared">{@received}</strong></p>
        <slot />
      </body>
    </html>
    """
  end

  def action(:show, params, component) do
    put_state(component, :received, params[:message])
  end
end
