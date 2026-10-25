defmodule HologramFeatureTests.Components.RealtimeEchoLayout do
  use Hologram.Component

  alias Hologram.UI.Runtime

  # Shared by Realtime.Page24 and Realtime.Page25, which both declare it, so its subscription
  # survives a navigation between them. The sender's own tab receives its broadcast only as the
  # self echo in the command's reply, so a reply that lands after that navigation is the one
  # delivery this layout gets.
  def init(_props, component, server) do
    {
      put_state(component, :received, "none"),
      put_subscription(server, {:room, 24})
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
        <p>Channel 24: <strong id="received-echo">{@received}</strong></p>
        <slot />
      </body>
    </html>
    """
  end

  def action(:show, params, component) do
    put_state(component, :received, params[:message])
  end
end
