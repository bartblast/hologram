defmodule Hologram.Template.ComponentTransformerTest do
  use Hologram.Test.UnitCase , async: true

  alias Hologram.Compiler.IR.{Alias, ModuleDefinition}
  alias Hologram.Template.ComponentTransformer
  alias Hologram.Template.Document.Component

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
    aliases = [%Alias{module: @module, as: [:Bcd]}]

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
    attrs = [{"attr_1", "value_1"}, {"attr_2", "value_2"}]

    result = ComponentTransformer.transform(@module_name, attrs, @children, @aliases)

    assert %ModuleDefinition{} = result.module_def

    expected = %Component{
      children: @children,
      module: @module,
      module_def: result.module_def,
      props: %{attr_1: "value_1", attr_2: "value_2"}
    }

    assert result == expected
  end
end
