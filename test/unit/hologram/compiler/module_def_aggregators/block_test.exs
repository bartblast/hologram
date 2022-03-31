defmodule Hologram.Compiler.ModuleDefAggregators.BlockTest do
  use Hologram.Test.UnitCase, async: false

  alias Hologram.Compiler.{ModuleDefAggregator, ModuleDefStore}
  alias Hologram.Compiler.IR.{Block, ModuleDefinition, ModuleType}
  alias Hologram.Test.Fixtures.{PlaceholderModule1, PlaceholderModule2}

  setup do
    ModuleDefStore.create()
    :ok
  end

  test "aggregate/1" do
    ir = %Block{expressions: [
      %ModuleType{module: PlaceholderModule1},
      %ModuleType{module: PlaceholderModule2}
    ]}

    ModuleDefAggregator.aggregate(ir)

    assert %ModuleDefinition{} = ModuleDefStore.get!(PlaceholderModule1)
    assert %ModuleDefinition{} = ModuleDefStore.get!(PlaceholderModule2)
  end
end
