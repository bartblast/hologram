defmodule Hologram.Compiler.ModuleDefAggregators.IfExpressionTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{ModuleDefAggregator, ModuleDefStore}
  alias Hologram.Compiler.IR.{ModuleDefinition, ModuleType, IfExpression, NilType}
  alias Hologram.Test.Fixtures.PlaceholderModule1

  setup do
    ModuleDefStore.create()
    :ok
  end

  test "condition is traversed" do
    ir = %IfExpression{
      condition: %ModuleType{module: PlaceholderModule1},
      do: %NilType{},
      else: %NilType{}
    }

    ModuleDefAggregator.aggregate(ir)

    assert %ModuleDefinition{} = ModuleDefStore.get(PlaceholderModule1)
  end

  test "do clause is traversed" do
    ir = %IfExpression{
      condition: %NilType{},
      do: %ModuleType{module: PlaceholderModule1},
      else: %NilType{}
    }

    ModuleDefAggregator.aggregate(ir)

    assert %ModuleDefinition{} = ModuleDefStore.get(PlaceholderModule1)
  end

  test "else clause is traversed" do
    ir = %IfExpression{
      condition: %NilType{},
      do: %NilType{},
      else: %ModuleType{module: PlaceholderModule1}
    }

    ModuleDefAggregator.aggregate(ir)

    assert %ModuleDefinition{} = ModuleDefStore.get(PlaceholderModule1)
  end
end
