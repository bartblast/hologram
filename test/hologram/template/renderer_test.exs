defmodule Hologram.Template.RendererTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.IR.{ModuleAttributeOperator, TupleType}
  alias Hologram.Template.Document.{Component, ElementNode, Expression, TextNode}
  alias Hologram.Template.Renderer

  @state %{}

  describe "render/2" do
    test "node list" do
      nodes = [
        %TextNode{content: "test_1"},
        %TextNode{content: "test_2"}
      ]

      result = Renderer.render(nodes, @state)
      expected = "test_1test_2"

      assert result == expected
    end

    test "component" do
      module = Hologram.Test.Fixtures.Template.Renderer.Module1
      virtual_dom = %Component{module: module}

      result = Renderer.render(virtual_dom, @state)
      expected = "<div>test template</div>"

      assert result == expected
    end

    test "element node" do
      virtual_dom = %ElementNode{tag: "div", attrs: %{}, children: []}

      result = Renderer.render(virtual_dom, @state)
      expected = "<div></div>"

      assert result == expected
    end

    test "expression" do
      virtual_dom = %Expression{
        ir: %TupleType{
          data: [%ModuleAttributeOperator{name: :a}]
        }
      }

      state = %{a: 123}

      result = Renderer.render(virtual_dom, state)
      expected = "123"

      assert result == expected
    end

    test "text node" do
      virtual_dom = %TextNode{content: "test"}

      result = Renderer.render(virtual_dom)
      expected = "test"

      assert result == expected
    end
  end
end
