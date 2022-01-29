defmodule Hologram.Compiler.CallGraphBuilder.UnaryPositiveOperatorTest do
  use Hologram.Test.UnitCase, async: false

  alias Hologram.Compiler.{CallGraph, CallGraphBuilder}
  alias Hologram.Compiler.IR.{IntegerType, UnaryPositiveOperator}
  alias Hologram.Test.Fixtures.PlaceholderModule1

  @module_defs %{}
  @templates %{}

  setup do
    CallGraph.create()
    :ok
  end

  test "build/4" do
    ir = %UnaryPositiveOperator{value: %IntegerType{value: 2}}
    from_vertex = PlaceholderModule1

    CallGraphBuilder.build(ir, @module_defs, @templates, from_vertex)

    assert CallGraph.num_vertices() == 0
    assert CallGraph.num_edges() == 0
  end
end
