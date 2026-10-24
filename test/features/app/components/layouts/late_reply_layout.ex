defmodule HologramFeatureTests.Components.LateReplyLayout do
  use Hologram.Component

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  alias Hologram.UI.Runtime
  alias HologramFeatureTests.Components.CommonLayoutStyles

  # Shared by both late reply pages, so the layout cid resolves on the destination too, to a new
  # instance of this same module, which has a clause for the reply. A reply that survives the
  # navigation does not raise there: it writes this result on the destination.
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

  def action(:record_layout_reply, _params, component) do
    put_state(component, :result, "layout_reply_ran")
  end

  # Stands in for a slow fetch: the reply is still in flight after the user has navigated away.
  def command(:slow_layout_command, _params, server) do
    Process.sleep(3_000)
    put_action(server, :record_layout_reply)
  end
end
