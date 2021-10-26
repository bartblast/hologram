defmodule Hologram.Template.ElementNodeRendererTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Template.VDOM.{ElementNode, TextNode}
  alias Hologram.Template.Renderer

  @bindings %{}

  test "non-slot" do
    attrs = %{
      attr_1: %{value: "test_attr_value_1", modifiers: []},
      on_click: %{value: "test_on_click", modifiers: []},
      attr_2: %{value: "test_attr_value_2", modifiers: []}
    }

    children = [
      %TextNode{content: "test_text"},
      %ElementNode{attrs: %{}, children: [], tag: "span"}
    ]

    element_node = %ElementNode{attrs: attrs, children: children, tag: "div"}
    result = Renderer.render(element_node, @bindings)

    expected =
      "<div attr_1=\"test_attr_value_1\" attr_2=\"test_attr_value_2\">test_text<span></span></div>"

    assert result == expected
  end

  test "slot" do
    children = [
      %TextNode{content: "test_text"},
      %ElementNode{attrs: %{}, children: [], tag: "span"}
    ]

    slot_node = %ElementNode{attrs: %{}, children: [], tag: "slot"}

    result = Renderer.render(slot_node, @bindings, default: children)
    expected = "test_text<span></span>"

    assert result == expected
  end
end
