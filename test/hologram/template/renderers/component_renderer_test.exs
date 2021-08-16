defmodule Hologram.Template.ComponentRendererTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.IR.{ModuleAttributeOperator, TupleType}
  alias Hologram.Template.Document.{Component, ElementNode, Expression, TextNode}
  alias Hologram.Template.Renderer

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

  test "slot" do
    module = Hologram.Test.Fixtures.Template.ComponentRenderer.Module4
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

    component = %Component{module: module, children: children}

    result = Renderer.render(component, state)
    expected = "<div>div node</div>\ntest_text123<h1></h1>\n<span>span node</span>"

    assert result == expected
  end
end
