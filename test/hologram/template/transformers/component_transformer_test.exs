defmodule Hologram.Template.ComponentTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR.{AliasDirective, ModuleDefinition}
  alias Hologram.Template.ComponentTransformer
  alias Hologram.Template.VDOM.{Component, Expression, TextNode}

  @aliases []
  @attrs []
  @children :children_stub
  @module Hologram.Test.Fixtures.PlaceholderComponent
  @module_name "Hologram.Test.Fixtures.PlaceholderComponent"

  test "non-aliased component" do
    result = ComponentTransformer.transform(@module_name, @attrs, @children, @aliases)

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
    aliases = [%AliasDirective{module: @module, as: [:Bcd]}]

    result = ComponentTransformer.transform(module_name, @attrs, @children, aliases)

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
    props = [{"attr_1", "text"}, {"attr_2", "abc{@k}xyz"}]

    result = ComponentTransformer.transform(@module_name, props, @children, @aliases)

    assert %ModuleDefinition{} = result.module_def

    expected = %Component{
      children: @children,
      module: @module,
      module_def: result.module_def,
      props: %{
        attr_1: [%TextNode{content: "text"}],
        attr_2: [
          %TextNode{content: "abc"},
          %Expression{
            ir: %Hologram.Compiler.IR.TupleType{
              data: [%Hologram.Compiler.IR.ModuleAttributeOperator{name: :k}]
            }
          },
          %TextNode{content: "xyz"}
        ]
      }
    }

    assert result == expected
  end
end
