defmodule Hologram.Template.ElementNodeRendererTest do
  use Hologram.TestCase, async: true

  alias Hologram.Template.Document.{ElementNode, TextNode}
  alias Hologram.Template.ElementNodeRenderer

  setup do
    [
      state: %{}
    ]
  end

  test "render/4", %{state: state} do
    attrs = %{attr_1: "test_attr_value_1", on_click: "test_on_click", attr_2: "test_attr_value_2"}

    children = [
      %TextNode{content: "test_text"},
      %ElementNode{attrs: %{}, children: [], tag: "span"}
    ]

    result = ElementNodeRenderer.render("div", attrs, children, state)

    expected =
      "<div attr_1=\"test_attr_value_1\" attr_2=\"test_attr_value_2\">test_text<span></span></div>"

    assert result == expected
  end
end
