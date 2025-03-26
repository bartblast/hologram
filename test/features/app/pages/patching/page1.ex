defmodule HologramFeatureTests.Patching.Page1 do
  use Hologram.Page

  alias Hologram.UI.Link
  alias Hologram.UI.Runtime
  alias HologramFeatureTests.Components.CommonLayoutStyles
  alias HologramFeatureTests.Patching.Page2

  route "/patching/1"

  layout HologramFeatureTests.Components.EmptyLayout

  def init(_params, component, _server) do
    put_state(component, root_elem_attr_1: nil, root_elem_attr_2: nil)
  end

  def template do
    ~HOLO"""
    <!DOCTYPE html>
    <html attr_1={@root_elem_attr_1} attr_2={@root_elem_attr_2}>
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <Runtime />
        <CommonLayoutStyles />
      </head>
      <body>
        <h1>Page 1 title</h1>
        <p>
          <button $click="add_root_elem_attr_1">Add root elem attr 1</button>
          <button $click="add_root_elem_attr_2">Add root elem attr 2</button>
          <button $click="change_root_elem_attr_1">Change root elem attr 1</button>
          <button $click="change_root_elem_attr_2">Change root elem attr 2</button>          
          <button $click="remove_root_elem_attr_1">Remove root elem attr 1</button>
          <button $click="remove_root_elem_attr_2">Remove root elem attr 2</button>
          <Link to={Page2}>Page 2 link</Link>
        </p>
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
