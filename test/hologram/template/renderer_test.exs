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
end
