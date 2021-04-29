defmodule Hologram.Transpiler.AdditionOperatorTransformerTest do
  use ExUnit.Case, async: true

  alias Hologram.Transpiler.AST.{AdditionOperator, IntegerType, Variable}
  alias Hologram.Transpiler.AdditionOperatorTransformer

  test "transform/5" do
    # a + 2
    left = {:a, [line: 1], nil}
    right = 2

    result = AdditionOperatorTransformer.transform(left, right, [:Test], [], [])

    expected =
      %AdditionOperator{
        left: %Variable{name: :a},
        right: %IntegerType{value: 2}
      }

    assert result == expected
  end
end
