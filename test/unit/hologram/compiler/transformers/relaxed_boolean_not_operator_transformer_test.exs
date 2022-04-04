defmodule Hologram.Compiler.RelaxedBooleanNotOperatorTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, RelaxedBooleanNotOperatorTransformer}
  alias Hologram.Compiler.IR.{BooleanType, RelaxedBooleanNotOperator}

  test "transform/3" do
    code = "!false"
    ast = ast(code)

    result = RelaxedBooleanNotOperatorTransformer.transform(ast, %Context{})

    expected = %RelaxedBooleanNotOperator{
      value: %BooleanType{value: false}
    }

    assert result == expected
  end
end
