defmodule Hologram.Template.ExpressionEvaluatorTest do
  use Hologram.Test.UnitCase , async: true

  alias Hologram.Compiler.IR.{IntegerType, TupleType}
  alias Hologram.Template.Document.Expression
  alias Hologram.Template.Evaluator

  test "evaluate/2" do
    ir = %Expression{
      ir: %TupleType{
        data: [
          %IntegerType{value: 1},
          %IntegerType{value: 2}
        ]
      }
    }

    result = Evaluator.evaluate(ir, %{})
    expected = 1

    assert result == expected
  end
end
