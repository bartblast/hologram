defmodule Hologram.Compiler.EvaluatorTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.Evaluator
  alias Hologram.Compiler.IR

  test "integer type" do
    ir = %IR.IntegerType{value: 123}
    assert Evaluator.evaluate(ir) == 123
  end
end
