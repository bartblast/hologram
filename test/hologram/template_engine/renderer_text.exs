defmodule Hologram.TemplateEngine.RendererTest do
  use ExUnit.Case, async: true

  alias Hologram.TemplateEngine.AST.Expression
  alias Hologram.TemplateEngine.AST.TagNode
  alias Hologram.TemplateEngine.AST.TextNode
  alias Hologram.TemplateEngine.Renderer
  alias Hologram.Transpiler.AST.ModuleAttributeOperator

  describe "render/2" do
    test "multiple nodes" do
      nodes = [
        %TextNode{text: "test_1"},
        %TextNode{text: "test_2"}
      ]

      result = Renderer.render(nodes, %{})
      expected = "test_1test_2"

      assert result == expected
    end

    test "tag node" do
      ast = %TagNode{
        attrs: %{attr_1: "test_attr_value_1", attr_2: "test_attr_value_2"},
        tag: "div",
        children: [
          %TextNode{text: "test_text"},
          %TagNode{attrs: %{}, children: [], tag: "span"}
        ]
      }

      result = Renderer.render(ast, %{})

      expected =
        "<div attr_1=\"test_attr_value_1\" attr_2=\"test_attr_value_2\">test_text<span></span></div>"

      assert result == expected
    end

    test "text node" do
      ast = %TextNode{text: "test"}

      result = Renderer.render(ast, %{})
      expected = "test"

      assert result == expected
    end

    test "expression" do
      ast = %Expression{ast: %ModuleAttributeOperator{name: :a}}
      state = %{a: 123}

      result = Renderer.render(ast, state)
      expected = "123"

      assert result == expected
    end

    test "attribute name" do
      node = %TagNode{attrs: %{":click" => "test"}, children: [], tag: "div"}

      result = Renderer.render(node, %{})
      expected = "<div holo-click=\"test\"></div>"

      assert result == expected
    end
  end

  describe "render_attr_name/1" do
    test "mapped" do
      assert Renderer.render_attr_name(":click") == "holo-click"
    end

    test "not mapped" do
      assert Renderer.render_attr_name("test") == "test"
    end
  end
end
