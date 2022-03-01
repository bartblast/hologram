defmodule Hologram.Compiler.MultiplicationOperatorTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, MultiplicationOperatorTransformer}
  alias Hologram.Compiler.IR.{IntegerType, MultiplicationOperator, Variable}

  test "transform/3" do
    code = "a * 2"
    ast = ast(code)

    result = MultiplicationOperatorTransformer.transform(ast, %Context{})

    expected = %MultiplicationOperator{
      left: %Variable{name: :a},
      right: %IntegerType{value: 2}
    }

    assert result == expected
  end
end
