defmodule HologramFeatureTests.Patching.Page3 do
  use Hologram.Page

  alias Hologram.UI.Runtime
  alias HologramFeatureTests.Components.CommonLayoutStyles

  route "/patching/3"

  layout HologramFeatureTests.Components.EmptyLayout

  def init(_params, component, _server) do
    put_state(component, class: "my_class_1")
  end

  def template do
    ~HOLO"""
    <!DOCTYPE html>
    <html class={@class}>
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <Runtime />
        <CommonLayoutStyles />
      </head>
      <body>
        <h1>Page 3 title</h1>
        <p>
          <button $click="change_to_class_2">Change to class 2</button>
          <button $click="change_to_class_3">Change to class 3</button>
          <button $click="remove_class">Remove class</button>
        </p>
      </body>
    </html>
    """
  end

  def action(:change_to_class_2, _params, component) do
    put_state(component, :class, "my_class_2")
  end

  def action(:change_to_class_3, _params, component) do
    put_state(component, :class, "my_class_3")
  end

  def action(:remove_class, _params, component) do
    put_state(component, :class, nil)
  end
end
