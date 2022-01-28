defmodule Hologram.Compiler.CallGraphBuilder.ElixirListTest do
  use Hologram.Test.UnitCase, async: false

  alias Hologram.Compiler.{CallGraph, CallGraphBuilder}
  alias Hologram.Compiler.IR.{ModuleType, UnaryPositiveOperator}
  alias Hologram.Test.Fixtures.{PlaceholderModule1, PlaceholderModule2}

  @module_defs %{}
  @templates %{}

  setup do
    CallGraph.create()
    :ok
  end

  test "build/4" do
    ir = %UnaryPositiveOperator{value: %ModuleType{module: PlaceholderModule2}}
    from_vertex = PlaceholderModule1

    CallGraphBuilder.build(ir, @module_defs, @templates, from_vertex)

    assert CallGraph.num_vertices() == 2
    assert CallGraph.num_edges() == 1

    assert CallGraph.has_edge?(PlaceholderModule1, PlaceholderModule2)
  end
end
