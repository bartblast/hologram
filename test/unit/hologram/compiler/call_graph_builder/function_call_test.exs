defmodule Hologram.Compiler.CallGraphBuilder.FunctionCallTest do
  use Hologram.Test.UnitCase, async: false

  alias Hologram.Compiler.{CallGraph, CallGraphBuilder, Reflection}
  alias Hologram.Compiler.IR.FunctionCall

  alias Hologram.Test.Fixtures.{
    PlaceholderModule1,
    PlaceholderModule2,
    PlaceholderModule3,
    PlaceholderModule4
  }

  @from_vertex {PlaceholderModule4, :test_fun_4a}

  @module_defs %{
    PlaceholderModule1 => Reflection.module_definition(PlaceholderModule1),
    PlaceholderModule2 => Reflection.module_definition(PlaceholderModule2),
    PlaceholderModule3 => Reflection.module_definition(PlaceholderModule3),
    PlaceholderModule4 => Reflection.module_definition(PlaceholderModule4)
  }

  @templates %{}

  setup do
    CallGraph.reset()
    :ok
  end

  test "non-standard lib module" do
    ir = %FunctionCall{module: PlaceholderModule2, function: :test_fun_2a}
    CallGraphBuilder.build(ir, @module_defs, @templates, @from_vertex)

    assert CallGraph.has_edge?(@from_vertex, {PlaceholderModule2, :test_fun_2a})
  end

  test "standard lib module" do
    ir = %FunctionCall{module: Kernel, function: :get_in}
    CallGraphBuilder.build(ir, @module_defs, @templates, @from_vertex)

    refute CallGraph.has_edge?(@from_vertex, {Kernel, :get_in})
  end

  test "args recursion" do
    args = [
      %FunctionCall{module: PlaceholderModule2, function: :test_fun_2a},
      %FunctionCall{module: PlaceholderModule3, function: :test_fun_3a}
    ]

    ir = %FunctionCall{module: PlaceholderModule1, function: :test_fun_1a, args: args}
    CallGraphBuilder.build(ir, @module_defs, @templates, @from_vertex)

    assert CallGraph.has_edge?(@from_vertex, {PlaceholderModule2, :test_fun_2a})
    assert CallGraph.has_edge?(@from_vertex, {PlaceholderModule3, :test_fun_3a})
  end
end
