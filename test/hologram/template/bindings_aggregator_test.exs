defmodule Hologram.Template.BindingsAggregatorTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR.{AdditionOperator, IntegerType, ModuleAttributeOperator, TupleType}
  alias Hologram.Compiler.Reflection
  alias Hologram.Template.BindingsAggregator
  alias Hologram.Template.VDOM.{Component, Expression, TextNode}

  test "layout component" do
    module_2 = Hologram.Test.Fixtures.Template.BindingsAggregator.Module2
    module_def = Reflection.module_definition(module_2)
    outer_bindings = %{a: 1, b: 2, c: 3, context: %{z: 9}}

    component = %Component{
      module: module_2,
      module_def: module_def,
      children: [],
      props: %{}
    }

    result = BindingsAggregator.aggregate(component, outer_bindings)

    expected = %{
      a: 1,
      b: 2,
      c: 333,
      context: %{z: 9},
      e: 444,
      f: 555
    }

    assert result == expected
  end

  test "non-layout component" do
    module_1 = Hologram.Test.Fixtures.Template.BindingsAggregator.Module1
    module_def = Reflection.module_definition(module_1)
    outer_bindings = %{a: 1, b: 2, c: 3, context: %{z: 9}}

    component = %Component{
      module: module_1,
      module_def: module_def,
      children: [],
      props: %{
        b: [
          %Expression{
            ir: %TupleType{
              data: [%IntegerType{value: 22}]
            }
          }
        ],
        d: [
          %Expression{
            ir: %TupleType{
              data: [%IntegerType{value: 6}]
            }
          }
        ],
        e: [
          %Expression{
            ir: %TupleType{
              data: [%IntegerType{value: 4}]
            }
          }
        ],
      }
    }

    result = BindingsAggregator.aggregate(component, outer_bindings)

    expected = %{
      b: 22,
      c: 333,
      context: %{z: 9},
      d: 6,
      e: 444,
      f: 555
    }

    assert result == expected
  end

  test "expression prop" do
    module_3 = Hologram.Test.Fixtures.Template.BindingsAggregator.Module3
    module_def = Reflection.module_definition(module_3)
    outer_bindings = %{a: 1, context: %{}}

    component = %Component{
      module: module_3,
      module_def: module_def,
      children: [],
      props: %{
        b: [
          %Expression{
            ir: %TupleType{
              data: [
                %AdditionOperator{
                  left: %IntegerType{value: 1},
                  right: %ModuleAttributeOperator{name: :a}
                }
              ]
            }
          }
        ],
      }
    }

    result = BindingsAggregator.aggregate(component, outer_bindings)
    expected = %{b: 2, context: %{}}

    assert result == expected
  end

  test "text prop" do
    module_4 = Hologram.Test.Fixtures.Template.BindingsAggregator.Module4
    module_def = Reflection.module_definition(module_4)
    outer_bindings = %{context: %{}}

    component = %Component{
      module: module_4,
      module_def: module_def,
      children: [],
      props: %{
        b: [%TextNode{content: "test_text_content"}]
      }
    }

    result = BindingsAggregator.aggregate(component, outer_bindings)
    expected = %{b: "test_text_content", context: %{}}

    assert result == expected
  end

  test "interpolated prop" do
    module_5 = Hologram.Test.Fixtures.Template.BindingsAggregator.Module5
    module_def = Reflection.module_definition(module_5)
    outer_bindings = %{a: 1, context: %{}}

    component = %Component{
      module: module_5,
      module_def: module_def,
      children: [],
      props: %{
        b: [
          %Expression{
            ir: %TupleType{
              data: [
                %AdditionOperator{
                  left: %IntegerType{value: 1},
                  right: %ModuleAttributeOperator{name: :a}
                }
              ]
            }
          },
          %TextNode{content: "test_text_content"}
        ],
      }
    }

    result = BindingsAggregator.aggregate(component, outer_bindings)
    expected = %{b: "2test_text_content", context: %{}}

    assert result == expected
  end
end
