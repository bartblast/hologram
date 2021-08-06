defmodule Hologram.Template.FunctionCallEvaluatorTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.IR.{FunctionCall, IntegerType, ListType}
  alias Hologram.Template.Evaluator

  test "evaluate/2" do
    params = [
      %ListType{
        data: [
          %IntegerType{value: 1},
          %IntegerType{value: 2}
        ]
      }
    ]

    ir = %FunctionCall{module: Kernel, function: :hd, params: params}

    result = Evaluator.evaluate(ir, %{})
    expected = 1

    assert result == expected
  end
end
