defmodule Hologram.Compiler.Aggregators.TupleTypeTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.Aggregator
  alias Hologram.Compiler.IR.{ModuleDefinition, ModuleType, TupleType}
  alias Hologram.Test.Fixtures.{PlaceholderModule1, PlaceholderModule2}

  test "aggregate/2" do
    ir = %TupleType{
      data: [
        %ModuleType{module: PlaceholderModule1},
        %ModuleType{module: PlaceholderModule2}
      ]
    }

    result = Aggregator.aggregate(ir, %{})

    assert Map.keys(result) == [PlaceholderModule1, PlaceholderModule2]
    assert %ModuleDefinition{} = result[PlaceholderModule1]
    assert %ModuleDefinition{} = result[PlaceholderModule2]
  end
end
