defmodule Hologram.Compiler.ModuleDefAggregators.FunctionCallTest do
  use Hologram.Test.UnitCase, async: false

  alias Hologram.Compiler.{ModuleDefAggregator, ModuleDefStore}
  alias Hologram.Compiler.IR.{FunctionCall, ModuleDefinition, ModuleType}
  alias Hologram.Test.Fixtures.Compiler.ModuleDefAggregators.FunctionCall.{Module1, Module2}

  setup do
    ModuleDefStore.create()
    :ok
  end

  test "aggregates called module" do
    ir = %FunctionCall{
      module: Module2,
      function: :test_fun_2a
    }

    ModuleDefAggregator.aggregate(ir)

    assert %ModuleDefinition{} = ModuleDefStore.get(Module2)
  end

  test "aggregates args" do
    ir = %FunctionCall{
      module: Kernel,
      args: [
        %ModuleType{module: Module1},
        %ModuleType{module: Module2}
      ]
    }

    ModuleDefAggregator.aggregate(ir)

    assert %ModuleDefinition{} = ModuleDefStore.get(Module1)
    assert %ModuleDefinition{} = ModuleDefStore.get(Module2)
  end
end
