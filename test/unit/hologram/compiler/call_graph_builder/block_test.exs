defmodule Hologram.Compiler.CallGraphBuilder.BlockTest do
  use Hologram.Test.UnitCase, async: false

  alias Hologram.Compiler.{CallGraph, CallGraphBuilder}
  alias Hologram.Compiler.IR.{Block, ModuleType}
  alias Hologram.Test.Fixtures.{PlaceholderModule1, PlaceholderModule2, PlaceholderModule3}

  @module_defs %{}
  @templates %{}

  setup do
    CallGraph.run()
    :ok
  end

  test "build/4" do
    ir = %Block{expressions: [
      %ModuleType{module: PlaceholderModule2},
      %ModuleType{module: PlaceholderModule3}
    ]}

    from_vertex = PlaceholderModule1
    CallGraphBuilder.build(ir, @module_defs, @templates, from_vertex)

    assert CallGraph.has_edge?(PlaceholderModule1, PlaceholderModule2)
    assert CallGraph.has_edge?(PlaceholderModule1, PlaceholderModule3)
  end
end
