defmodule Hologram.Compiler.CallGraphBuilder.IfExpressionTest do
  use Hologram.Test.UnitCase, async: false

  alias Hologram.Compiler.{CallGraph, CallGraphBuilder}
  alias Hologram.Compiler.IR.{ModuleType, IfExpression, NilType}
  alias Hologram.Test.Fixtures.{PlaceholderModule1, PlaceholderModule2}

  @module_defs %{}
  @templates %{}

  setup do
    CallGraph.run()
    :ok
  end

  test "condition is traversed" do
    ir = %IfExpression{
      condition: %ModuleType{module: PlaceholderModule2},
      do: %NilType{},
      else: %NilType{}
    }

    from_vertex = PlaceholderModule1
    CallGraphBuilder.build(ir, @module_defs, @templates, from_vertex)

    assert CallGraph.has_edge?(PlaceholderModule1, PlaceholderModule2)
  end

  test "do clause is traversed" do
    ir = %IfExpression{
      condition: %NilType{},
      do: %ModuleType{module: PlaceholderModule2},
      else: %NilType{}
    }

    from_vertex = PlaceholderModule1
    CallGraphBuilder.build(ir, @module_defs, @templates, from_vertex)

    assert CallGraph.has_edge?(PlaceholderModule1, PlaceholderModule2)
  end

  test "else clause is traversed" do
    ir = %IfExpression{
      condition: %NilType{},
      do: %NilType{},
      else: %ModuleType{module: PlaceholderModule2}
    }

    from_vertex = PlaceholderModule1
    CallGraphBuilder.build(ir, @module_defs, @templates, from_vertex)

    assert CallGraph.has_edge?(PlaceholderModule1, PlaceholderModule2)
  end
end
