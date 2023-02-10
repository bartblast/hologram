defmodule Hologram.Compiler.MultiplicationOperatorTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR.{IntegerType, MultiplicationOperator, Variable}
  alias Hologram.Compiler.MultiplicationOperatorTransformer

  test "transform/3" do
    code = "a * 2"
    ast = ast(code)

    result = MultiplicationOperatorTransformer.transform(ast)

    expected = %MultiplicationOperator{
      left: %Variable{name: :a},
      right: %IntegerType{value: 2}
    }

    assert result == expected
  end
end
