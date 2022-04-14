defmodule Hologram.Compiler.NotEqualToOperatorTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, NotEqualToOperatorTransformer}
  alias Hologram.Compiler.IR.{IntegerType, NotEqualToOperator}

  test "transform/3" do
    code = "1 != 2"
    ast = ast(code)

    result = NotEqualToOperatorTransformer.transform(ast, %Context{})

    expected = %NotEqualToOperator{
      left: %IntegerType{value: 1},
      right: %IntegerType{value: 2}
    }

    assert result == expected
  end
end
