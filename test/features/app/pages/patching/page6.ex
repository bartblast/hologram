defmodule HologramFeatureTests.Patching.Page6 do
  use Hologram.Page

  alias Hologram.UI.Link
  alias Hologram.UI.Runtime
  alias HologramFeatureTests.Components.CommonLayoutStyles
  alias HologramFeatureTests.Patching.Page7

  route "/patching/6"

  layout HologramFeatureTests.Components.EmptyLayout

  def init(_params, component, _server) do
    put_state(component, body_elem_attr_1: nil, body_elem_attr_2: nil)
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
      <body attr_1={@body_elem_attr_1} attr_2={@body_elem_attr_2}>
        <h1>Page 6 title</h1>
        <p>
          <button $click="add_body_elem_attr_1">Add body elem attr 1</button>
          <button $click="add_body_elem_attr_2">Add body elem attr 2</button>
          <button $click="change_body_elem_attr_1">Change body elem attr 1</button>
          <button $click="change_body_elem_attr_2">Change body elem attr 2</button>          
          <button $click="remove_body_elem_attr_1">Remove body elem attr 1</button>
          <button $click="remove_body_elem_attr_2">Remove body elem attr 2</button>
          <Link to={Page7}>Page 7 link</Link>
        </p>
      </body>
    </html>
    """
  end

  def action(:add_body_elem_attr_1, _params, component) do
    put_state(component, :body_elem_attr_1, "value_1a")
  end

  def action(:add_body_elem_attr_2, _params, component) do
    put_state(component, :body_elem_attr_2, "value_2a")
  end

  def action(:change_body_elem_attr_1, _params, component) do
    put_state(component, :body_elem_attr_1, "value_1b")
  end

  def action(:change_body_elem_attr_2, _params, component) do
    put_state(component, :body_elem_attr_2, "value_2b")
  end

  def action(:remove_body_elem_attr_1, _params, component) do
    put_state(component, :body_elem_attr_1, nil)
  end

  def action(:remove_body_elem_attr_2, _params, component) do
    put_state(component, :body_elem_attr_2, nil)
  end
end
