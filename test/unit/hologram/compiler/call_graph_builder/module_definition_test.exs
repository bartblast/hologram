defmodule Hologram.Compiler.CallGraphBuilder.ModuleDefinitionTest do
  use Hologram.Test.UnitCase, async: false

  alias Hologram.Compiler.{CallGraph, CallGraphBuilder, Reflection}
  alias Hologram.Compiler.IR.{FunctionDefinition, ModuleDefinition, ModuleType}
  alias Hologram.Test.Fixtures.{PlaceholderModule1, PlaceholderModule2}
  alias Hologram.Test.Fixtures.Compiler.CallGraphBuilder.ModuleDefinition.{Module4, Module5}

  @from_vertex nil
  @templates %{}

  setup do
    CallGraph.run()
    :ok
  end

  test "module that isn't in the call graph yet" do
    module_def = Reflection.module_definition(PlaceholderModule1)
    module_defs = %{PlaceholderModule1 => module_def}

    CallGraphBuilder.build(module_def, module_defs, @templates, @from_vertex)

    assert CallGraph.has_vertex?(PlaceholderModule1)
  end

  test "module that is already in the call graph" do
    ir = %ModuleDefinition{
      module: PlaceholderModule1,
      functions: []
    }

    CallGraph.add_vertex(PlaceholderModule1)
    module_defs = %{}

    CallGraphBuilder.build(ir, module_defs, @templates, @from_vertex)

    assert CallGraph.has_vertex?(PlaceholderModule1)
  end

  test "functions traversing" do
    module_def_1 = %ModuleDefinition{
      module: PlaceholderModule1,
      functions: [
        %FunctionDefinition{
          module: PlaceholderModule1,
          name: :test_fun,
          body: [
            %ModuleType{module: PlaceholderModule2}
          ]
        }
      ]
    }

    module_def_2 = %ModuleDefinition{
      module: PlaceholderModule2
    }

    module_defs = %{
      PlaceholderModule1 => module_def_1,
      PlaceholderModule2 => module_def_2
    }

    CallGraphBuilder.build(module_def_1, module_defs, @templates, @from_vertex)

    assert CallGraph.has_edge?({PlaceholderModule1, :test_fun}, PlaceholderModule2)
  end

  test "template traversing" do
    opts = [
      app_path: "#{@fixtures_path}/compiler/call_graph_builder/module_definition",
      templatables: [HologramE2E.DefaultLayout]
    ]

    %{templates: templates} = compile(opts)

    module_defs = %{
      Module4 => Reflection.module_definition(Module4),
      Module5 => Reflection.module_definition(Module5)
    }

    CallGraph.run()
    CallGraphBuilder.build(module_defs[Module4], module_defs, templates, @from_vertex)

    assert CallGraph.has_vertex?(Module5)
    assert CallGraph.has_edge?(Module4, {Module4, :template})
    assert CallGraph.has_edge?({Module4, :template}, Module5)
  end
end
