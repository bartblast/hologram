defmodule Hologram.Compiler.IRAggregators.IfExpressionTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{IRAggregator, IRStore}
  alias Hologram.Compiler.IR.{ModuleDefinition, ModuleType, IfExpression, NilType}
  alias Hologram.Test.Fixtures.PlaceholderModule1

  setup do
    IRStore.create()
    :ok
  end

  test "condition is traversed" do
    ir = %IfExpression{
      condition: %ModuleType{module: PlaceholderModule1},
      do: %NilType{},
      else: %NilType{}
    }

    IRAggregator.aggregate(ir)

    assert %ModuleDefinition{} = IRStore.get(PlaceholderModule1)
  end

  test "do clause is traversed" do
    ir = %IfExpression{
      condition: %NilType{},
      do: %ModuleType{module: PlaceholderModule1},
      else: %NilType{}
    }

    IRAggregator.aggregate(ir)

    assert %ModuleDefinition{} = IRStore.get(PlaceholderModule1)
  end

  test "else clause is traversed" do
    ir = %IfExpression{
      condition: %NilType{},
      do: %NilType{},
      else: %ModuleType{module: PlaceholderModule1}
    }

    IRAggregator.aggregate(ir)

    assert %ModuleDefinition{} = IRStore.get(PlaceholderModule1)
  end
end
