defmodule Hologram.Compiler.AdditionOperatorTransformerTest do
  use ExUnit.Case, async: true

  alias Hologram.Compiler.AST.{AdditionOperator, IntegerType, Variable}
  alias Hologram.Compiler.AdditionOperatorTransformer

  test "transform/5" do
    # a + 2
    left = {:a, [line: 1], nil}
    right = 2

    context = [module: [:Test], imports: [], aliases: []]
    result = AdditionOperatorTransformer.transform(left, right, context)

    expected =
      %AdditionOperator{
        left: %Variable{name: :a},
        right: %IntegerType{value: 2}
      }

    assert result == expected
  end
end
