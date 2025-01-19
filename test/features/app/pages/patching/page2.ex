defmodule HologramFeatureTests.Patching.Page2 do
  use Hologram.Page

  alias Hologram.UI.Runtime
  alias HologramFeatureTests.Components.CommonLayoutStyles

  route "/patching/2"

  layout HologramFeatureTests.Components.EmptyLayout

  def template do
    ~H"""
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

  def action(:add_root_elem_attr_1, _params, component) do
    put_state(component, :root_elem_attr_1, "value_1a")
  end

  def action(:add_root_elem_attr_2, _params, component) do
    put_state(component, :root_elem_attr_2, "value_2a")
  end

  def action(:change_root_elem_attr_1, _params, component) do
    put_state(component, :root_elem_attr_1, "value_1b")
  end

  def action(:change_root_elem_attr_2, _params, component) do
    put_state(component, :root_elem_attr_2, "value_2b")
  end

  def action(:remove_root_elem_attr_1, _params, component) do
    put_state(component, :root_elem_attr_1, nil)
  end

  def action(:remove_root_elem_attr_2, _params, component) do
    put_state(component, :root_elem_attr_2, nil)
  end
end
