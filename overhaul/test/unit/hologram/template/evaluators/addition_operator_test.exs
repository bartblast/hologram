defmodule Hologram.Template.Evaluator.AdditionOperatorTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR.{AdditionOperator, IntegerType}
  alias Hologram.Template.Evaluator

  test "evaluate/2" do
    ir = %AdditionOperator{
      left: %IntegerType{value: 1},
      right: %IntegerType{value: 2}
    }

    result = Evaluator.evaluate(ir, %{})
    assert result == 3
  end
end
