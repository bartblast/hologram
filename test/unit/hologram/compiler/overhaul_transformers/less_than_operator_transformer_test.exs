defmodule Hologram.Compiler.LessThanOperatorTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR.IntegerType
  alias Hologram.Compiler.IR.LessThanOperator
  alias Hologram.Compiler.LessThanOperatorTransformer

  test "transform/3" do
    code = "1 < 2"
    ast = ast(code)

    result = LessThanOperatorTransformer.transform(ast)

    expected = %LessThanOperator{
      left: %IntegerType{value: 1},
      right: %IntegerType{value: 2}
    }

    assert result == expected
  end
end
