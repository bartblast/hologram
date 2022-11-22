defmodule Hologram.Template.ComponentTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.Context
  alias Hologram.Compiler.IR.AdditionOperator
  alias Hologram.Compiler.IR.AliasDirective
  alias Hologram.Compiler.IR.IntegerType
  alias Hologram.Compiler.IR.ModuleDefinition
  alias Hologram.Compiler.IR.TupleType
  alias Hologram.Template.ComponentTransformer
  alias Hologram.Template.VDOM.Component
  alias Hologram.Template.VDOM.Expression
  alias Hologram.Template.VDOM.TextNode

  @children :children_stub
  @context %Context{}
  @module Hologram.Test.Fixtures.PlaceholderComponent
  @module_name "Hologram.Test.Fixtures.PlaceholderComponent"
  @props []

  test "non-aliased component" do
    result = ComponentTransformer.transform(@module_name, @props, @children, @context)

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

    result = ComponentTransformer.transform(module_name, @props, @children, context)

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
      {"attr_1", [literal: "test"]},
      {"attr_2", [expression: "{1 + 2}"]}
    ]

    result = ComponentTransformer.transform(@module_name, props, @children, @context)

    assert %ModuleDefinition{} = result.module_def

    expected = %Component{
      children: @children,
      module: @module,
      module_def: result.module_def,
      props: %{
        attr_1: [%TextNode{content: "test"}],
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
        ]
      }
    }

    assert result == expected
  end
end
