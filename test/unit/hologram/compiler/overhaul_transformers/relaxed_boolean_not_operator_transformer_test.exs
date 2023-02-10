defmodule Hologram.Compiler.RelaxedBooleanNotOperatorTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR.{BooleanType, RelaxedBooleanNotOperator}
  alias Hologram.Compiler.RelaxedBooleanNotOperatorTransformer

  test "transform/3" do
    code = "!false"
    ast = ast(code)

    result = RelaxedBooleanNotOperatorTransformer.transform(ast)

    expected = %RelaxedBooleanNotOperator{
      value: %BooleanType{value: false}
    }

    assert result == expected
  end
end
