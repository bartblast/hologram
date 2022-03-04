defmodule Hologram.Compiler.CallGraphBuilder.CaseExpressionTest do
  use Hologram.Test.UnitCase, async: false

  alias Hologram.Compiler.{CallGraph, CallGraphBuilder}
  alias Hologram.Compiler.IR.{CaseExpression, IntegerType, ModuleType}
  alias Hologram.Test.Fixtures.{PlaceholderModule1, PlaceholderModule2, PlaceholderModule3, PlaceholderModule4, PlaceholderModule5, PlaceholderModule6}

  @module_defs %{}
  @templates %{}

  setup do
    CallGraph.create()
    :ok
  end

  test "build/4" do
    ir = %CaseExpression{
      clauses: [
        %{
          bindings: [],
          body: [
            %ModuleType{module: PlaceholderModule3},
            %ModuleType{module: PlaceholderModule4}
          ],
          pattern: %IntegerType{value: 1}
        },
        %{
          bindings: [],
          body: [
            %ModuleType{module: PlaceholderModule5},
            %ModuleType{module: PlaceholderModule6}
          ],
          pattern: %IntegerType{value: 2}
        }
      ],
      condition: %ModuleType{module: PlaceholderModule2}
    }

    from_vertex = PlaceholderModule1
    CallGraphBuilder.build(ir, @module_defs, @templates, from_vertex)

    assert CallGraph.num_vertices() == 6
    assert CallGraph.num_edges() == 5

    assert CallGraph.has_edge?(PlaceholderModule1, PlaceholderModule2)
    assert CallGraph.has_edge?(PlaceholderModule1, PlaceholderModule3)
    assert CallGraph.has_edge?(PlaceholderModule1, PlaceholderModule4)
    assert CallGraph.has_edge?(PlaceholderModule1, PlaceholderModule5)
    assert CallGraph.has_edge?(PlaceholderModule1, PlaceholderModule6)
  end

end
