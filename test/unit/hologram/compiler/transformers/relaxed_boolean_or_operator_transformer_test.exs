defmodule Hologram.Compiler.RelaxedBooleanOrOperatorTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, RelaxedBooleanOrOperatorTransformer}
  alias Hologram.Compiler.IR.{IntegerType, RelaxedBooleanOrOperator}

  test "transform/3" do
    code = "1 || 2"
    ast = ast(code)

    result = RelaxedBooleanOrOperatorTransformer.transform(ast, %Context{})

    expected = %RelaxedBooleanOrOperator{
      left: %IntegerType{value: 1},
      right: %IntegerType{value: 2}
    }

    assert result == expected
  end
end
