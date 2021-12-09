defmodule Hologram.Compiler.IRAggregators.FunctionDefinitionTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{IRAggregator, ModuleDefinitionStore}
  alias Hologram.Compiler.IR.{FunctionDefinition, ModuleDefinition, ModuleType}
  alias Hologram.Test.Fixtures.{PlaceholderModule1, PlaceholderModule2}

  setup do
    ModuleDefinitionStore.create()
    :ok
  end

  test "aggregate/1" do
    ir = %FunctionDefinition{
      body: [
        %ModuleType{module: PlaceholderModule1},
        %ModuleType{module: PlaceholderModule2}
      ]
    }

    IRAggregator.aggregate(ir)

    assert %ModuleDefinition{} = ModuleDefinitionStore.get(PlaceholderModule1)
    assert %ModuleDefinition{} = ModuleDefinitionStore.get(PlaceholderModule2)
  end
end
