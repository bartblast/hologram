defmodule Hologram.Compiler.AdditionOperatorTransformerTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.{Context, AdditionOperatorTransformer}
  alias Hologram.Compiler.IR.{AdditionOperator, IntegerType, Variable}

  test "transform/3" do
    code = "a + 2"
    {:+, _, [left, right]} = ast(code)

    result = AdditionOperatorTransformer.transform(left, right, %Context{})

    expected = %AdditionOperator{
      left: %Variable{name: :a},
      right: %IntegerType{value: 2}
    }

    assert result == expected
  end
end
