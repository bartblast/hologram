defmodule Hologram.TemplateEngine.RendererTest do
  use ExUnit.Case, async: true

  alias Hologram.TemplateEngine.AST.TagNode
  alias Hologram.TemplateEngine.AST.TextNode
  alias Hologram.TemplateEngine.Renderer

  test "tag node" do
    ast = %TagNode{attrs: %{attr_1: "test_attr_value_1", attr_2: "test_attr_value_2"}, tag: "div", children: [
      %TextNode{text: "test_text"},
      %TagNode{attrs: %{}, children: [], tag: "span"}
    ]}

    result = Renderer.render(ast, %{})
    expected = "<div attr_1=\"test_attr_value_1\" attr_2=\"test_attr_value_2\">test_text<span></span></div>"

    assert result == expected
  end

  test "text node" do
    ast = %TextNode{text: "test"}

    result = Renderer.render(ast, %{})
    expected = "test"

    assert result == expected
  end
end
