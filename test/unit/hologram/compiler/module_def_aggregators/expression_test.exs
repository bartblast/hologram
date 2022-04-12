defmodule Hologram.Compiler.ModuleDefAggregator.ExpressionTest do
  use Hologram.Test.UnitCase, async: false

  alias Hologram.Compiler.{ModuleDefAggregator, ModuleDefStore}
  alias Hologram.Compiler.IR.{ModuleDefinition, ModuleType, TupleType}
  alias Hologram.Template.VDOM.Expression
  alias Hologram.Test.Fixtures.{PlaceholderModule1, PlaceholderModule2}

  setup do
    ModuleDefStore.run()
    :ok
  end

  test "aggregate/1" do
    ir = %Expression{
      ir: %TupleType{
        data: [
          %ModuleType{module: PlaceholderModule1},
          %ModuleType{module: PlaceholderModule2}
        ]
      }
    }

    ModuleDefAggregator.aggregate(ir)

    assert %ModuleDefinition{} = ModuleDefStore.get!(PlaceholderModule1)
    assert %ModuleDefinition{} = ModuleDefStore.get!(PlaceholderModule2)
  end
end
