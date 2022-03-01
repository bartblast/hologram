defmodule Hologram.Compiler.UnaryNegativeOperatorTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, UnaryNegativeOperatorTransformer}
  alias Hologram.Compiler.IR.{IntegerType, UnaryNegativeOperator, Variable}

  test "transform/3" do
    code = "-2"
    ast = ast(code)

    result = UnaryNegativeOperatorTransformer.transform(ast, %Context{})

    expected = %UnaryNegativeOperator{
      value: %IntegerType{value: 2}
    }

    assert result == expected
  end
end
