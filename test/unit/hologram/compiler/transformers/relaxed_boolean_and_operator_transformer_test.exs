defmodule Hologram.Compiler.RelaxedBooleanAndOperatorTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, RelaxedBooleanAndOperatorTransformer}
  alias Hologram.Compiler.IR.{IntegerType, RelaxedBooleanAndOperator}

  test "transform/3" do
    code = "1 && 2"
    ast = ast(code)

    result = RelaxedBooleanAndOperatorTransformer.transform(ast, %Context{})

    expected = %RelaxedBooleanAndOperator{
      left: %IntegerType{value: 1},
      right: %IntegerType{value: 2}
    }

    assert result == expected
  end
end
