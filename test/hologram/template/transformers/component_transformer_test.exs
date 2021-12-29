defmodule Hologram.Template.ComponentTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.Context
  alias Hologram.Compiler.IR.{AdditionOperator, AliasDirective, IntegerType, ModuleAttributeOperator, ModuleDefinition, TupleType}
  alias Hologram.Template.ComponentTransformer
  alias Hologram.Template.VDOM.{Component, Expression, TextNode}

  @attrs []
  @children :children_stub
  @context %Context{}
  @module Hologram.Test.Fixtures.PlaceholderComponent
  @module_name "Hologram.Test.Fixtures.PlaceholderComponent"

  test "non-aliased component" do
    result = ComponentTransformer.transform(@module_name, @attrs, @children, @context)

    assert %ModuleDefinition{} = result.module_def

    expected = %Component{
      module: @module,
      module_def: result.module_def,
      props: %{},
      children: @children
    }

    assert result == expected
  end

  test "aliased component" do
    module_name = "Bcd"

    context = %Context{
      aliases: [%AliasDirective{module: @module, as: [:Bcd]}]
    }

    result = ComponentTransformer.transform(module_name, @attrs, @children, context)

    assert %ModuleDefinition{} = result.module_def

    expected = %Component{
      children: @children,
      module: @module,
      module_def: result.module_def,
      props: %{}
    }

    assert result == expected
  end

  test "props" do
    props = [
      {:literal, "attr_1", "text"},
      {:expression, "attr_2", "1 + 2"},
      {:literal, "attr_3", "abc{@k}xyz"}
    ]

    result = ComponentTransformer.transform(@module_name, props, @children, @context)

    assert %ModuleDefinition{} = result.module_def

    expected = %Component{
      children: @children,
      module: @module,
      module_def: result.module_def,
      props: %{
        attr_1: [%TextNode{content: "text"}],
        attr_2: [
          %Expression{
            ir: %TupleType{
              data: [
                %AdditionOperator{
                  left: %IntegerType{value: 1},
                  right: %IntegerType{value: 2}
                }
              ]
            }
          }
        ],
        attr_3: [
          %TextNode{content: "abc"},
          %Expression{
            ir: %TupleType{
              data: [%ModuleAttributeOperator{name: :k}]
            }
          },
          %TextNode{content: "xyz"}
        ]
      }
    }

    assert result == expected
  end
end
