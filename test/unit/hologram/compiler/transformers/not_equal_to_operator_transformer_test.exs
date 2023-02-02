defmodule Hologram.Compiler.NotEqualToOperatorTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR.{IntegerType, NotEqualToOperator}
  alias Hologram.Compiler.NotEqualToOperatorTransformer

  test "transform/3" do
    code = "1 != 2"
    ast = ast(code)

    result = NotEqualToOperatorTransformer.transform(ast)

    expected = %NotEqualToOperator{
      left: %IntegerType{value: 1},
      right: %IntegerType{value: 2}
    }

    assert result == expected
  end
end
