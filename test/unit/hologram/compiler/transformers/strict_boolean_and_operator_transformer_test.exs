defmodule Hologram.Compiler.StrictBooleanAndOperatorTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, StrictBooleanAndOperatorTransformer}
  alias Hologram.Compiler.IR.{BooleanType, StrictBooleanAndOperator}

  test "transform/3" do
    code = "true and false"
    ast = ast(code)

    result = StrictBooleanAndOperatorTransformer.transform(ast, %Context{})

    expected = %StrictBooleanAndOperator{
      left: %BooleanType{value: true},
      right: %BooleanType{value: false}
    }

    assert result == expected
  end
end
