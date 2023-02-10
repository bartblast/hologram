defmodule Hologram.Compiler.AdditionOperatorTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.AdditionOperatorTransformer
  alias Hologram.Compiler.IR.{AdditionOperator, IntegerType, Variable}

  test "transform/3" do
    code = "a + 2"
    ast = ast(code)

    result = AdditionOperatorTransformer.transform(ast)

    expected = %AdditionOperator{
      left: %Variable{name: :a},
      right: %IntegerType{value: 2}
    }

    assert result == expected
  end
end
