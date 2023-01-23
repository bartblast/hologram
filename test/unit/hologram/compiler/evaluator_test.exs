defmodule Hologram.Compiler.EvaluatorTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.Evaluator
  alias Hologram.Compiler.IR

  test "addition operator" do
    ir = %IR.AdditionOperator{
      left: %IR.IntegerType{value: 1},
      right: %IR.IntegerType{value: 2}
    }

    result = Evaluator.evaluate(ir)

    assert result == 3
  end

  test "integer type" do
    ir = %IR.IntegerType{value: 123}
    result = Evaluator.evaluate(ir)

    assert result == 123
  end
end
