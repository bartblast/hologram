defmodule Hologram.Template.ComponentRendererTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR.{IntegerType, ModuleAttributeOperator, TupleType}
  alias Hologram.Compiler.Reflection
  alias Hologram.Template.Document.{Component, ElementNode, Expression, TextNode}
  alias Hologram.Template.Renderer

  @module_4 Hologram.Test.Fixtures.Template.ComponentRenderer.Module4
  @module_5 Hologram.Test.Fixtures.Template.ComponentRenderer.Module5
  @module_6 Hologram.Test.Fixtures.Template.ComponentRenderer.Module6
  @module_7 Hologram.Test.Fixtures.Template.ComponentRenderer.Module7
  @module_8 Hologram.Test.Fixtures.Template.ComponentRenderer.Module8

  test "html only in template" do
    module = Hologram.Test.Fixtures.Template.ComponentRenderer.Module1
    module_def = Reflection.module_definition(module)
    state = %{context: nil}
    component = %Component{module: module, module_def: module_def}

    result = Renderer.render(component, state)
    expected = "<span>test</span>"

    assert result == expected
  end

  test "html and nested un-aliased component in template" do
    module = Hologram.Test.Fixtures.Template.ComponentRenderer.Module2
    module_def = Reflection.module_definition(module)
    state = %{context: nil}
    component = %Component{module: module, module_def: module_def}

    result = Renderer.render(component, state)
    expected = "<div><span>test</span></div>"

    assert result == expected
  end

  test "html and nested aliased component in template" do
    module = Hologram.Test.Fixtures.Template.ComponentRenderer.Module3
    module_def = Reflection.module_definition(module)
    state = %{context: nil}
    component = %Component{module: module, module_def: module_def}

    result = Renderer.render(component, state)
    expected = "<div><span>test</span></div>"

    assert result == expected
  end

  test "non-nested slot" do
    state = %{a: 123, context: nil}

    expression = %Expression{
      ir: %TupleType{
        data: [%ModuleAttributeOperator{name: :a}]
      }
    }

    children = [
      %TextNode{content: "test_text"},
      expression,
      %ElementNode{attrs: %{}, children: [], tag: "h1"}
    ]

    props = %{
      a: [
        %Expression{
          ir: %TupleType{
            data: [%IntegerType{value: 123}]
          }
        }
      ]
    }

    module_def = Reflection.module_definition(@module_4)

    component = %Component{
      module: @module_4,
      module_def: module_def,
      children: children,
      props: props
    }

    result = Renderer.render(component, state)
    expected = "<div>div node</div>\ntest_text123<h1></h1>\n<span>span node</span>"

    assert result == expected
  end

  test "nested slot" do
    state = %{a: 1, b: 2, context: nil}

    expression_1 = %Expression{
      ir: %TupleType{
        data: [%ModuleAttributeOperator{name: :a}]
      }
    }

    expression_2 = %Expression{
      ir: %TupleType{
        data: [%ModuleAttributeOperator{name: :b}]
      }
    }

    module_def_5 = Reflection.module_definition(@module_5)

    a_value = [
      %Expression{
        ir: %TupleType{
          data: [%IntegerType{value: 1}]
        }
      }
    ]

    b_value = [
      %Expression{
        ir: %TupleType{
          data: [%IntegerType{value: 2}]
        }
      }
    ]

    component_2 = %Component{
      module: @module_5,
      module_def: module_def_5,
      children: [
        %TextNode{content: "text_node_2"},
        expression_2
      ],
      props: %{b: b_value}
    }

    module_def_4 = Reflection.module_definition(@module_4)

    component_1 = %Component{
      module: @module_4,
      module_def: module_def_4,
      children: [
        %TextNode{content: "text_node_1"},
        expression_1,
        component_2
      ],
      props: %{a: a_value}
    }

    result = Renderer.render(component_1, state)

    expected =
      "<div>div node</div>\ntext_node_11<h1>h1 node</h1>\ntext_node_22\n<p>p node</p>\n<span>span node</span>"

    assert result == expected
  end

  test "layout component" do
    module_def = Reflection.module_definition(@module_6)
    state = %{x: 123, context: nil}

    component = %Component{
      module: @module_6,
      module_def: module_def,
      children: [],
      props: %{}
    }

    result = Renderer.render(component, state)
    assert result == "abc123bcd"
  end

  test "expression prop" do
    module_def = Reflection.module_definition(@module_7)
    state = %{context: nil}

    component = %Component{
      module: @module_7,
      module_def: module_def,
      children: [],
      props: %{
        x: [
          %Expression{
            ir: %TupleType{
              data: [%IntegerType{value: 123}]
            }
          }
        ]
      }
    }

    result = Renderer.render(component, state)
    assert result == "abc123bcd"
  end

  test "text prop" do
    module_def = Reflection.module_definition(@module_7)
    state = %{context: nil}

    component = %Component{
      module: @module_7,
      module_def: module_def,
      children: [],
      props: %{
        x: [
          %TextNode{content: "qwerty"}
        ]
      }
    }

    result = Renderer.render(component, state)
    assert result == "abcqwertybcd"
  end

  test "interpolated prop" do
    module_def = Reflection.module_definition(@module_7)
    state = %{context: nil}

    component = %Component{
      module: @module_7,
      module_def: module_def,
      children: [],
      props: %{
        x: [
          %TextNode{content: "k"},
          %Expression{
            ir: %TupleType{
              data: [%IntegerType{value: 123}]
            }
          },
          %TextNode{content: "m"}
        ]
      }
    }

    result = Renderer.render(component, state)
    assert result == "abck123mbcd"
  end

  test "context is merged into state" do
    module_def = Reflection.module_definition(@module_8)
    state = %{context: %{x: 123}}

    component = %Component{
      module: @module_8,
      module_def: module_def,
      children: [],
      props: %{}
    }

    result = Renderer.render(component, state)
    assert result == "abc123bcd"
  end
end
