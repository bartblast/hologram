defmodule Hologram.Template.RendererTest do
  use Hologram.TestCase, async: true

  alias Hologram.Template.VirtualDOM.Expression
  alias Hologram.Template.VirtualDOM.TagNode
  alias Hologram.Template.VirtualDOM.TextNode
  alias Hologram.Template.Renderer
  alias Hologram.Compiler.IR.ModuleAttributeOperator

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
      virtual_dom = %TagNode{
        attrs: %{attr_1: "test_attr_value_1", attr_2: "test_attr_value_2"},
        tag: "div",
        children: [
          %TextNode{text: "test_text"},
          %TagNode{attrs: %{}, children: [], tag: "span"}
        ]
      }

      result = Renderer.render(virtual_dom, %{})

      expected =
        "<div attr_1=\"test_attr_value_1\" attr_2=\"test_attr_value_2\">test_text<span></span></div>"

      assert result == expected
    end

    test "text node" do
      virtual_dom = %TextNode{text: "test"}

      result = Renderer.render(virtual_dom, %{})
      expected = "test"

      assert result == expected
    end

    test "expression" do
      virtual_dom = %Expression{ir: %ModuleAttributeOperator{name: :a}}
      state = %{a: 123}

      result = Renderer.render(virtual_dom, state)
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
