defmodule HologramFeatureTests.Components.DefaultLayout do
  use Hologram.Component
  alias Hologram.UI.Runtime

  def template do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <Runtime />
      </head>
      <body style="padding: 25px">
        <slot />
      </body>
    </html>
    """
  end
end
