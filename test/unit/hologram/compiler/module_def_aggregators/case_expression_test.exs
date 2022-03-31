defmodule Hologram.Compiler.ModuleDefAggregators.CaseExpressionTest do
  use Hologram.Test.UnitCase, async: false

  alias Hologram.Compiler.{ModuleDefAggregator, ModuleDefStore}
  alias Hologram.Compiler.IR.{CaseExpression, IntegerType, ModuleDefinition, ModuleType}

  alias Hologram.Test.Fixtures.{
    PlaceholderModule1,
    PlaceholderModule2,
    PlaceholderModule3,
    PlaceholderModule4,
    PlaceholderModule5
  }

  setup do
    ModuleDefStore.create()
    :ok
  end

  test "aggregate/1" do
    ir = %CaseExpression{
      clauses: [
        %{
          bindings: [],
          body: [
            %ModuleType{module: PlaceholderModule2},
            %ModuleType{module: PlaceholderModule3}
          ],
          pattern: %IntegerType{value: 1}
        },
        %{
          bindings: [],
          body: [
            %ModuleType{module: PlaceholderModule4},
            %ModuleType{module: PlaceholderModule5}
          ],
          pattern: %IntegerType{value: 2}
        }
      ],
      condition: %ModuleType{module: PlaceholderModule1}
    }

    ModuleDefAggregator.aggregate(ir)

    assert %ModuleDefinition{} = ModuleDefStore.get!(PlaceholderModule1)
    assert %ModuleDefinition{} = ModuleDefStore.get!(PlaceholderModule2)
    assert %ModuleDefinition{} = ModuleDefStore.get!(PlaceholderModule3)
    assert %ModuleDefinition{} = ModuleDefStore.get!(PlaceholderModule4)
    assert %ModuleDefinition{} = ModuleDefStore.get!(PlaceholderModule5)
  end
end
