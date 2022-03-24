defmodule Hologram.Compiler.CallGraphBuilder.ModuleTypeTest do
  use Hologram.Test.UnitCase, async: false

  alias Hologram.Compiler.{CallGraph, CallGraphBuilder}
  alias Hologram.Compiler.IR.ModuleType
  alias Hologram.Test.Fixtures.{PlaceholderModule1, PlaceholderModule2}

  @module_defs %{}
  @templates %{}

  setup do
    CallGraph.reset()
    :ok
  end

  test "non-standard lib module" do
    ir = %ModuleType{module: PlaceholderModule2}
    from_vertex = PlaceholderModule1
    CallGraphBuilder.build(ir, @module_defs, @templates, from_vertex)

    assert CallGraph.has_edge?(PlaceholderModule1, PlaceholderModule2)
  end

  test "standard lib module" do
    ir = %ModuleType{module: Kernel}
    from_vertex = PlaceholderModule1
    CallGraphBuilder.build(ir, @module_defs, @templates, from_vertex)

    refute CallGraph.has_edge?(PlaceholderModule1, Kernel)
  end
end
