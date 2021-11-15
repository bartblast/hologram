defmodule Hologram.Compiler.Aggregators.FunctionCallTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.Aggregator
  alias Hologram.Compiler.IR.{FunctionCall, ModuleDefinition, ModuleType}
  alias Hologram.Test.Fixtures.Compiler.Aggregators.FunctionCall.{Module1, Module2}

  test "aggregates called module" do
    ir = %FunctionCall{
      module: Module2,
      function: :test_fun_2a
    }

    result = Aggregator.aggregate(ir, %{})

    assert Map.keys(result) == [Module2]
    assert %ModuleDefinition{} = result[Module2]
  end

  test "aggregates args" do
    ir = %FunctionCall{
      module: Kernel,
      args: [
        %ModuleType{module: Module1},
        %ModuleType{module: Module2},
      ]
    }

    result = Aggregator.aggregate(ir, %{})

    assert Map.keys(result) == [Module1, Module2]
    assert %ModuleDefinition{} = result[Module1]
    assert %ModuleDefinition{} = result[Module2]
  end
end
