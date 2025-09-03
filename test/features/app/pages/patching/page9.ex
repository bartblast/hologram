defmodule HologramFeatureTests.Patching.Page9 do
  use Hologram.Page

  alias Hologram.UI.Runtime
  alias HologramFeatureTests.Components.CommonLayoutStyles

  route "/patching/9"

  layout HologramFeatureTests.Components.EmptyLayout

  def init(_params, component, _server) do
    put_state(component, class: nil)
  end

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
      <body class={@class}>
        <h1>Page 9 title</h1>
        <p>
          <button $click="add_class">Add class</button>
        </p>
      </body>
    </html>
    """
  end

  def action(:add_class, _params, component) do
    put_state(component, :class, "my_class")
  end
end
