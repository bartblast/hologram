defmodule HologramFeatureTests.Patching.Page7 do
  use Hologram.Page

  alias Hologram.UI.Runtime
  alias HologramFeatureTests.Components.CommonLayoutStyles

  route "/patching/7"

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
      <body attr_3="value_3">
        <h1>Page 7 title</h1>
      </body>
    </html>
    """
  end
end
