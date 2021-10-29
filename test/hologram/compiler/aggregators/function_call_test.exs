defmodule Hologram.Compiler.Aggregators.FunctionCallTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.Aggregator
  alias Hologram.Compiler.IR.{ModuleDefinition, FunctionCall}
  alias Hologram.Test.Fixtures.Compiler.Aggregators.FunctionCall.Module2

  test "aggregate/2" do
    ir = %FunctionCall{
      module: Module2,
      function: :test_fun_2a
    }

    result = Aggregator.aggregate(ir, %{})

    assert Map.keys(result) == [Module2]
    assert %ModuleDefinition{} = result[Module2]
  end
end
