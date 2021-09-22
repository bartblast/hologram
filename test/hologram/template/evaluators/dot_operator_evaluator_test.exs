defmodule Hologram.Template.DotOperatorEvaluatorTest do
  use Hologram.Test.UnitCase , async: true

  alias Hologram.Compiler.IR.{AtomType, DotOperator, IntegerType, MapType}
  alias Hologram.Template.Evaluator

  test "evaluate/2" do
    ir = %DotOperator{
      left: %MapType{
        data: [
          {%AtomType{value: :a}, %IntegerType{value: 1}}
        ]
      },
      right: %AtomType{value: :a}
    }

    result = Evaluator.evaluate(ir, %{})
    expected = 1

    assert result == expected
  end
end
