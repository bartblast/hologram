defmodule Hologram.Compiler.RelaxedBooleanAndOperatorTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR.{IntegerType, RelaxedBooleanAndOperator}
  alias Hologram.Compiler.RelaxedBooleanAndOperatorTransformer

  test "transform/3" do
    code = "1 && 2"
    ast = ast(code)

    result = RelaxedBooleanAndOperatorTransformer.transform(ast)

    expected = %RelaxedBooleanAndOperator{
      left: %IntegerType{value: 1},
      right: %IntegerType{value: 2}
    }

    assert result == expected
  end
end
