defmodule Hologram.Compiler.CallGraphBuilder.AnonymousFunctionCallTest do
  use Hologram.Test.UnitCase, async: false

  alias Hologram.Compiler.{CallGraph, CallGraphBuilder, Reflection}
  alias Hologram.Compiler.IR.AnonymousFunctionCall
  alias Hologram.Compiler.IR.FunctionCall

  alias Hologram.Test.Fixtures.{
    PlaceholderModule1,
    PlaceholderModule2,
    PlaceholderModule3
  }

  @from_vertex {PlaceholderModule1, :test_fun_1a}

  @module_defs %{
    PlaceholderModule1 => Reflection.module_definition(PlaceholderModule1),
    PlaceholderModule2 => Reflection.module_definition(PlaceholderModule2),
    PlaceholderModule3 => Reflection.module_definition(PlaceholderModule3)
  }

  @templates %{}

  setup do
    CallGraph.run()
    :ok
  end

  test "args recursion" do
    args = [
      %FunctionCall{module: PlaceholderModule2, function: :test_fun_2a},
      %FunctionCall{module: PlaceholderModule3, function: :test_fun_3a}
    ]

    ir = %AnonymousFunctionCall{name: :test_anon, args: args}
    CallGraphBuilder.build(ir, @module_defs, @templates, @from_vertex)

    assert CallGraph.has_edge?(@from_vertex, {PlaceholderModule2, :test_fun_2a})
    assert CallGraph.has_edge?(@from_vertex, {PlaceholderModule3, :test_fun_3a})
  end
end
