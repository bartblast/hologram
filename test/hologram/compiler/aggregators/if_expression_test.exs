defmodule Hologram.Compiler.Aggregators.IfExpressionTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.Aggregator
  alias Hologram.Compiler.IR.{ModuleDefinition, ModuleType, IfExpression, NilType}
  alias Hologram.Test.Fixtures.PlaceholderModule1

  describe "aggregate/2" do
    test "condition is traversed" do
      ir = %IfExpression{
        condition: %ModuleType{module: PlaceholderModule1},
        do: %NilType{},
        else: %NilType{}
      }

      result = Aggregator.aggregate(ir, %{})

      assert Map.keys(result) == [PlaceholderModule1]
      assert %ModuleDefinition{} = result[PlaceholderModule1]
    end

    test "do clause is traversed" do
      ir = %IfExpression{
        condition: %NilType{},
        do: %ModuleType{module: PlaceholderModule1},
        else: %NilType{}
      }

      result = Aggregator.aggregate(ir, %{})

      assert Map.keys(result) == [PlaceholderModule1]
      assert %ModuleDefinition{} = result[PlaceholderModule1]
    end

    test "else clause is traversed" do
      ir = %IfExpression{
        condition: %NilType{},
        do: %NilType{},
        else: %ModuleType{module: PlaceholderModule1}
      }

      result = Aggregator.aggregate(ir, %{})

      assert Map.keys(result) == [PlaceholderModule1]
      assert %ModuleDefinition{} = result[PlaceholderModule1]
    end
  end
end
