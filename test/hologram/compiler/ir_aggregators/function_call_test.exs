defmodule Hologram.Compiler.IRAggregators.FunctionCallTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{IRAggregator, ModuleDefinitionStore}
  alias Hologram.Compiler.IR.{FunctionCall, ModuleDefinition, ModuleType}
  alias Hologram.Test.Fixtures.Compiler.Aggregators.FunctionCall.{Module1, Module2}

  setup do
    ModuleDefinitionStore.create()
    :ok
  end

  test "aggregates called module" do
    ir = %FunctionCall{
      module: Module2,
      function: :test_fun_2a
    }

    IRAggregator.aggregate(ir)

    assert %ModuleDefinition{} = ModuleDefinitionStore.get(Module2)
  end

  test "aggregates args" do
    ir = %FunctionCall{
      module: Kernel,
      args: [
        %ModuleType{module: Module1},
        %ModuleType{module: Module2},
      ]
    }

    IRAggregator.aggregate(ir)

    assert %ModuleDefinition{} = ModuleDefinitionStore.get(Module1)
    assert %ModuleDefinition{} = ModuleDefinitionStore.get(Module2)
  end
end
