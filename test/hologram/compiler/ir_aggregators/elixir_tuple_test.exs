defmodule Hologram.Compiler.IRAggregators.ElixirTupleTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{IRAggregator, ModuleDefStore}
  alias Hologram.Compiler.IR.{ModuleDefinition, ModuleType}
  alias Hologram.Test.Fixtures.{PlaceholderModule1, PlaceholderModule2}

  setup do
    ModuleDefStore.create()
    :ok
  end

  test "aggregate/1" do
    ir = {
      %ModuleType{module: PlaceholderModule1},
      %ModuleType{module: PlaceholderModule2}
    }

    IRAggregator.aggregate(ir)

    assert %ModuleDefinition{} = ModuleDefStore.get(PlaceholderModule1)
    assert %ModuleDefinition{} = ModuleDefStore.get(PlaceholderModule2)
  end
end
