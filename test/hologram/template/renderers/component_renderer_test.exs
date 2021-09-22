defmodule Hologram.Template.ComponentRendererTest do
  use Hologram.Test.UnitCase , async: true

  alias Hologram.Compiler.IR.{ModuleAttributeOperator, TupleType}
  alias Hologram.Template.Document.{Component, ElementNode, Expression, TextNode}
  alias Hologram.Template.Renderer

  @module_4 Hologram.Test.Fixtures.Template.ComponentRenderer.Module4
  @module_5 Hologram.Test.Fixtures.Template.ComponentRenderer.Module5

  test "html only in template" do
    module = Hologram.Test.Fixtures.Template.ComponentRenderer.Module1
    state = %{}

    result = Renderer.render(%Component{module: module}, state)
    expected = "<span>test</span>"

    assert result == expected
  end

  test "html and nested un-aliased component in template" do
    module = Hologram.Test.Fixtures.Template.ComponentRenderer.Module2
    state = %{}

    result = Renderer.render(%Component{module: module}, state)
    expected = "<div><span>test</span></div>"

    assert result == expected
  end

  test "html and nested aliased component in template" do
    module = Hologram.Test.Fixtures.Template.ComponentRenderer.Module3
    state = %{}

    result = Renderer.render(%Component{module: module}, state)
    expected = "<div><span>test</span></div>"

    assert result == expected
  end

  test "non-nested slot" do
    state = %{a: 123}

    expression =
      %Expression{
        ir: %TupleType{
          data: [%ModuleAttributeOperator{name: :a}]
        }
      }

    children = [
      %TextNode{content: "test_text"},
      expression,
      %ElementNode{attrs: %{}, children: [], tag: "h1"}
    ]

    component = %Component{module: @module_4, children: children}

    result = Renderer.render(component, state)
    expected = "<div>div node</div>\ntest_text123<h1></h1>\n<span>span node</span>"

    assert result == expected
  end

  test "nested slot" do
    state = %{a: 1, b: 2}

    expression_1 =
      %Expression{
        ir: %TupleType{
          data: [%ModuleAttributeOperator{name: :a}]
        }
      }

    expression_2 =
      %Expression{
        ir: %TupleType{
          data: [%ModuleAttributeOperator{name: :b}]
        }
      }

    component_2 = %Component{
      module: @module_5,
      children: [
        %TextNode{content: "text_node_2"},
        expression_2
      ]
    }

    component_1 = %Component{
      module: @module_4,
      children: [
        %TextNode{content: "text_node_1"},
        expression_1,
        component_2
      ]
    }

    result = Renderer.render(component_1, state)
    expected = "<div>div node</div>\ntext_node_11<h1>h1 node</h1>\ntext_node_22\n<p>p node</p>\n<span>span node</span>"

    assert result == expected
  end
end
