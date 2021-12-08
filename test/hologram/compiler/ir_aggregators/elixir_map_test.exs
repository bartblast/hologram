defmodule Hologram.Compiler.IRAggregators.ElixirMapTest do
  use Hologram.Test.UnitCase, async: true
  
  alias Hologram.Compiler.{IRAggregator, IRStore}
  alias Hologram.Compiler.IR.{ModuleDefinition, ModuleType}
  alias Hologram.Test.Fixtures.{PlaceholderModule1, PlaceholderModule2}

  setup do
    IRStore.create()
    :ok
  end

  test "aggregate/1" do
    ir = %{
      :a => 1,
      %ModuleType{module: PlaceholderModule1} => %ModuleType{module: PlaceholderModule2}
    }

    IRAggregator.aggregate(ir)

    assert %ModuleDefinition{} = IRStore.get(PlaceholderModule1)
    assert %ModuleDefinition{} = IRStore.get(PlaceholderModule2)
  end
end
