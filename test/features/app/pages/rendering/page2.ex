defmodule HologramFeatureTests.Rendering.Page2 do
  use Hologram.Page

  alias Hologram.UI.Runtime
  alias HologramFeatureTests.Components.CommonLayoutStyles

  route "/rendering/2"

  layout HologramFeatureTests.Components.EmptyLayout

  def template do
    ~HOLO"""
    <!DOCTYPE html>
    <html attr_1="value_1">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <Runtime />
        <CommonLayoutStyles />
      </head>
      <body>
        Page2
      </body>
    </html>
    """
  end
end
