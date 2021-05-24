defmodule Hologram.Template.RendererTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.IR.ModuleAttributeOperator
  alias Hologram.Template.Renderer
  alias Hologram.Template.VirtualDOM.{Expression, ElementNode, TextNode}

  setup do
    [
      state: %{}
    ]
  end

  describe "render/2" do
    test "node list", %{state: state} do
      nodes = [
        %TextNode{text: "test_1"},
        %TextNode{text: "test_2"}
      ]

      result = Renderer.render(nodes, state)
      expected = "test_1test_2"

      assert result == expected
    end

    test "expression" do
      virtual_dom = %Expression{ir: %ModuleAttributeOperator{name: :a}}
      state = %{a: 123}

      result = Renderer.render(virtual_dom, state)
      expected = "123"

      assert result == expected
    end

    test "tag node", %{state: state} do
      virtual_dom = %ElementNode{tag: "div", attrs: %{}, children: []}

      result = Renderer.render(virtual_dom, state)
      expected = "<div></div>"

      assert result == expected
    end

    test "text node" do
      virtual_dom = %TextNode{text: "test"}

      result = Renderer.render(virtual_dom)
      expected = "test"

      assert result == expected
    end
  end
end
