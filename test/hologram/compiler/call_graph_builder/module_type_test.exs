defmodule Hologram.Compiler.CallGraphBuilder.ModuleTypeTest do
  use Hologram.Test.UnitCase, async: false

  alias Hologram.Compiler.{CallGraph, CallGraphBuilder}
  alias Hologram.Compiler.IR.ModuleType
  alias Hologram.Test.Fixtures.{PlaceholderModule1, PlaceholderModule2}

  setup do
    CallGraph.create()
    :ok
  end

  test "non-standard lib module" do
    ir = %ModuleType{module: PlaceholderModule2}
    from_vertex = PlaceholderModule1
    result = CallGraphBuilder.build(ir, %{}, from_vertex)

    assert CallGraph.num_vertices() == 2
    assert CallGraph.num_edges() == 1

    assert CallGraph.has_edge?(PlaceholderModule1, PlaceholderModule2)
  end

  test "standard lib module" do
    ir = %ModuleType{module: Kernel}
    from_vertex = PlaceholderModule1
    result = CallGraphBuilder.build(ir, %{}, from_vertex)

    assert CallGraph.num_vertices() == 0
  end
end
