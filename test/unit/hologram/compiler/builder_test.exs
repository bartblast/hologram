defmodule Hologram.Compiler.BuilderTest do
  use Hologram.Test.UnitCase, async: false

  alias Hologram.Compiler.{
    Builder,
    CallGraph,
    CallGraphBuilder,
  }

  @module Hologram.Test.Fixtures.Compiler.Builder.Module1

  setup do
    opts = [
      app_path: @fixtures_path <> "/compiler/builder",
      templatables: [HologramE2E.DefaultLayout]
    ]

    compile(opts)
  end

  test "build/1", %{module_defs: module_defs, templates: templates} do
    from_vertex = nil

    CallGraph.run()
    CallGraphBuilder.build(@module, module_defs, templates, from_vertex)
    call_graph = CallGraph.get()

    result = Builder.build(@module, module_defs, call_graph)

    assert result =~ ~r/class Elixir_Hologram_Test_Fixtures_Compiler_Builder_Module1/
    assert result =~ ~r/class Elixir_Hologram_Test_Fixtures_Compiler_Builder_Module3/

    refute result =~ ~r/Elixir_Hologram_Test_Fixtures_Compiler_Builder_Module2/
  end
end
