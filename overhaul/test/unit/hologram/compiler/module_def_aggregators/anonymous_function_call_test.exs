defmodule Hologram.Compiler.ModuleDefAggregator.AnonymousFunctionCallTest do
  use Hologram.Test.UnitCase, async: false

  alias Hologram.Compiler.{ModuleDefAggregator, ModuleDefStore}
  alias Hologram.Compiler.IR.{AnonymousFunctionCall, ModuleDefinition, ModuleType}
  alias Hologram.Test.Fixtures.PlaceholderModule1
  alias Hologram.Test.Fixtures.PlaceholderModule2

  setup do
    ModuleDefStore.run()
    :ok
  end

  test "aggregates args" do
    ir = %AnonymousFunctionCall{
      name: :test,
      args: [
        %ModuleType{module: PlaceholderModule1},
        %ModuleType{module: PlaceholderModule2}
      ]
    }

    ModuleDefAggregator.aggregate(ir)

    assert %ModuleDefinition{} = ModuleDefStore.get!(PlaceholderModule1)
    assert %ModuleDefinition{} = ModuleDefStore.get!(PlaceholderModule2)
  end
end
