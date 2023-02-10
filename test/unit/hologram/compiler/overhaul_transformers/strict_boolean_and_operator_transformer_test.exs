defmodule Hologram.Compiler.StrictBooleanAndOperatorTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR.{BooleanType, StrictBooleanAndOperator}
  alias Hologram.Compiler.StrictBooleanAndOperatorTransformer

  test "transform/3" do
    code = "true and false"
    ast = ast(code)

    result = StrictBooleanAndOperatorTransformer.transform(ast)

    expected = %StrictBooleanAndOperator{
      left: %BooleanType{value: true},
      right: %BooleanType{value: false}
    }

    assert result == expected
  end
end
