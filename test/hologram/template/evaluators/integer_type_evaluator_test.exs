defmodule Hologram.Template.IntegerTypeEvaluatorTest do
  use Hologram.Test.UnitCase , async: true

  alias Hologram.Compiler.IR.IntegerType
  alias Hologram.Template.Evaluator

  test "evaluate/2" do
    ir = %IntegerType{value: 123}

    result = Evaluator.evaluate(ir, %{})
    expected = 123

    assert result == expected
  end
end
