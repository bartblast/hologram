defmodule HologramFeatureTests.Patching.Page2 do
  use Hologram.Page

  alias Hologram.UI.Runtime
  alias HologramFeatureTests.Components.CommonLayoutStyles

  route "/patching/2"

  layout HologramFeatureTests.Components.EmptyLayout

  def template do
    ~HOLO"""
    <!DOCTYPE html>
    <html attr_3="value_3">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <Runtime />
        <CommonLayoutStyles />
      </head>
      <body>
        <h1>Page 2 title</h1>
      </body>
    </html>
    """
  end
end
