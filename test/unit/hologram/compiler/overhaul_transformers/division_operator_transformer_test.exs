defmodule Hologram.Compiler.DivisionOperatorTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.DivisionOperatorTransformer
  alias Hologram.Compiler.IR.{DivisionOperator, IntegerType, Variable}

  test "transform/3" do
    code = "a / 2"
    ast = ast(code)

    result = DivisionOperatorTransformer.transform(ast)

    expected = %DivisionOperator{
      left: %Variable{name: :a},
      right: %IntegerType{value: 2}
    }

    assert result == expected
  end
end
