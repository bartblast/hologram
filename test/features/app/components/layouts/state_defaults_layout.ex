defmodule HologramFeatureTests.Components.StateDefaultsLayout do
  use Hologram.Component

  alias Hologram.UI.Runtime
  alias HologramFeatureTests.Components.CommonLayoutStyles

  # No init/3 on purpose: the declared default is the state the layout starts with.
  state :greeting, :string, default: "layout default"

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
        <p id="layout_greeting">{@greeting}</p>
        <slot />
      </body>
    </html>
    """
  end
end
