defmodule Hologram.Compiler.Aggregators.ModuleTypeTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.Aggregator
  alias Hologram.Compiler.IR.{ModuleDefinition, ModuleType}
  alias Hologram.Test.Fixtures.Compiler.Aggregators.ModuleType.Module1
  alias Hologram.Test.Fixtures.Compiler.Aggregators.ModuleType.Module2
  alias Hologram.Test.Fixtures.PlaceholderModule1

  test "non standard lib module that isn't in the accumulator yet is added" do
    ir = %ModuleType{module: PlaceholderModule1}
    result = Aggregator.aggregate(ir, %{})

    assert Map.keys(result) == [PlaceholderModule1]
    assert %ModuleDefinition{} = result[PlaceholderModule1]
  end

  test "module that is in the accumulator already is ignored" do
    ir = %ModuleType{module: PlaceholderModule1}

    result = Aggregator.aggregate(ir, %{})
    result = Aggregator.aggregate(ir, result)

    assert Map.keys(result) == [PlaceholderModule1]
    assert %ModuleDefinition{} = result[PlaceholderModule1]
  end

  test "standard lib module is ignored" do
    ir = %ModuleType{module: Kernel}
    result = Aggregator.aggregate(ir, %{})

    assert result == %{}
  end

  test "module functions are traversed" do
    ir = %ModuleType{module: Module1}
    result = Aggregator.aggregate(ir, %{})

    assert Map.keys(result) == [Module1, Module2]
    assert %ModuleDefinition{} = result[Module1]
    assert %ModuleDefinition{} = result[Module2]
  end
end
