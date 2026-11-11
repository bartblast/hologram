defmodule HologramFeatureTests.Components.RefsLayout do
  use Hologram.Component

  alias Hologram.UI.Runtime
  alias HologramFeatureTests.Components.CommonLayoutStyles

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
        <header $ref="layout_header">Refs layout header</header>
        <slot />
      </body>
    </html>
    """
  end
end
