defmodule Hologram.Template.ListTypeEvaluatorTest do
  use Hologram.Test.UnitCase , async: true

  alias Hologram.Compiler.IR.{IntegerType, ListType}
  alias Hologram.Template.Evaluator

  test "evaluate/2" do
    ir = %ListType{
      data: [
        %IntegerType{value: 1},
        %IntegerType{value: 2}
      ]
    }

    result = Evaluator.evaluate(ir, %{})
    expected = [1, 2]

    assert result == expected
  end
end
