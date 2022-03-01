defmodule Hologram.Compiler.CallGraphBuilder.SubtractionOperatorTest do
  use Hologram.Test.UnitCase, async: false

  alias Hologram.Compiler.{CallGraph, CallGraphBuilder, Reflection}
  alias Hologram.Compiler.IR.{FunctionCall, SubtractionOperator}

  alias Hologram.Test.Fixtures.{
    PlaceholderModule1,
    PlaceholderModule2,
    PlaceholderModule3
  }

  @module_defs %{
    PlaceholderModule1 => Reflection.module_definition(PlaceholderModule1),
    PlaceholderModule2 => Reflection.module_definition(PlaceholderModule2),
    PlaceholderModule3 => Reflection.module_definition(PlaceholderModule3)
  }

  @templates %{}

  setup do
    CallGraph.create()
    :ok
  end

  test "build/4" do
    from_vertex = PlaceholderModule1

    ir = %SubtractionOperator{
      left: %FunctionCall{module: PlaceholderModule2, function: :test_fun_2a},
      right: %FunctionCall{module: PlaceholderModule3, function: :test_fun_3a}
    }

    CallGraphBuilder.build(ir, @module_defs, @templates, from_vertex)

    assert CallGraph.num_edges() == 2
    assert CallGraph.has_edge?(PlaceholderModule1, {PlaceholderModule2, :test_fun_2a})
    assert CallGraph.has_edge?(PlaceholderModule1, {PlaceholderModule3, :test_fun_3a})
  end
end
