defmodule Hologram.Compiler.BuilderTest do
  use Hologram.Test.UnitCase, async: false

  alias Hologram.Compiler.{
    Builder,
    CallGraph,
    CallGraphBuilder,
    ModuleDefAggregator,
    ModuleDefStore
  }

  setup do
    ModuleDefStore.restart()
    CallGraph.restart()

    :ok
  end

  test "build/1" do
    module = Hologram.Test.Fixtures.Compiler.Builder.Module1

    ModuleDefAggregator.aggregate(module)
    module_defs = ModuleDefStore.get_all()
    templates = %{}
    from_vertex = nil

    CallGraphBuilder.build(module, module_defs, templates, from_vertex)
    call_graph = CallGraph.get()

    result = Builder.build(module, module_defs, call_graph)

    assert result =~ ~r/class Elixir_Hologram_Test_Fixtures_Compiler_Builder_Module1/
    assert result =~ ~r/class Elixir_Hologram_Test_Fixtures_Compiler_Builder_Module3/

    refute result =~ ~r/Elixir_Hologram_Test_Fixtures_Compiler_Builder_Module2/
  end
end
