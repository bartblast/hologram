defmodule Hologram.Compiler.BooleanAndOperatorTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, BooleanAndOperatorTransformer}
  alias Hologram.Compiler.IR.{BooleanAndOperator, IntegerType}

  test "transform/3" do
    code = "1 && 2"
    ast = ast(code)

    result = BooleanAndOperatorTransformer.transform(ast, %Context{})

    expected = %BooleanAndOperator{
      left: %IntegerType{value: 1},
      right: %IntegerType{value: 2}
    }

    assert result == expected
  end
end
