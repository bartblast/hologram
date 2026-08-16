defmodule HologramFeatureTests.Components.NavigationLayout do
  use Hologram.Component

  alias Hologram.UI.Runtime
  alias HologramFeatureTests.Components.CommonLayoutStyles

  # The shell every page in this layout shares. The container's scroll position lives only in its
  # DOM node, so it survives a navigation only while the node itself does.
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
        <div id="shell" style="height: 40px; overflow: auto">
          <p style="height: 400px">tall enough to scroll</p>
        </div>
        <slot />
      </body>
    </html>
    """
  end
end
