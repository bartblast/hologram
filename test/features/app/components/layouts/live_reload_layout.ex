defmodule HologramFeatureTests.Components.LiveReloadLayout do
  use Hologram.Component

  alias Hologram.UI.Runtime
  alias HologramFeatureTests.Components.CommonLayoutStyles

  # Links a stylesheet the live reload tests write and rewrite, to see a CSS change reach the tab.
  def template do
    ~HOLO"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <Runtime />
        <CommonLayoutStyles />
        <link rel="stylesheet" href="/assets/live_reload.css" />
      </head>
      <body>
        <slot />
      </body>
    </html>
    """
  end
end
