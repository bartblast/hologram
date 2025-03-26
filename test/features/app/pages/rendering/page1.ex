defmodule HologramFeatureTests.Rendering.Page1 do
  use Hologram.Page

  alias Hologram.UI.Runtime
  alias HologramFeatureTests.Components.CommonLayoutStyles

  route "/rendering/1"

  layout HologramFeatureTests.Components.EmptyLayout

  def template do
    ~HOLO"""
    <!DOCTYPE html>
    <html>
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <Runtime />
        <CommonLayoutStyles />
      </head>
      <body>
        Page1
      </body>
    </html>
    """
  end
end
