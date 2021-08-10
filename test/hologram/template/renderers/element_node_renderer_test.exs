defmodule Hologram.Template.ElementNodeRendererTest do
  use Hologram.TestCase, async: true

  alias Hologram.Template.Document.{ElementNode, TextNode}
  alias Hologram.Template.Renderer

  @state %{}

  test "render/2" do
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
    result = Renderer.render(element_node, @state)

    expected =
      "<div attr_1=\"test_attr_value_1\" attr_2=\"test_attr_value_2\">test_text<span></span></div>"

    assert result == expected
  end
end
