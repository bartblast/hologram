defmodule Hologram.Compiler.EqualToOperatorTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.EqualToOperatorTransformer
  alias Hologram.Compiler.IR.{EqualToOperator, IntegerType}

  test "transform/3" do
    code = "1 == 2"
    ast = ast(code)

    result = EqualToOperatorTransformer.transform(ast)

    expected = %EqualToOperator{
      left: %IntegerType{value: 1},
      right: %IntegerType{value: 2}
    }

    assert result == expected
  end
end
