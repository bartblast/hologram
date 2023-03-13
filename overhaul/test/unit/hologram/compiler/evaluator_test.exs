defmodule Hologram.Compiler.EvaluatorTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.Evaluator
  alias Hologram.Compiler.IR

  test "evaluate/1" do
    ir = %IR.IntegerType{value: 123}
    result = Evaluator.evaluate(ir)

    assert result == 123
  end
end
