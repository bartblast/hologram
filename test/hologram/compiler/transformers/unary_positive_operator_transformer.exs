defmodule Hologram.Compiler.UnaryPositiveOperatorTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, UnaryPositiveOperatorTransformer}
  alias Hologram.Compiler.IR.{UnaryPositiveOperator, IntegerType, Variable}

  test "transform/3" do
    code = "+2"
    ast = ast(code)

    result = UnaryPositiveOperatorTransformer.transform(ast, %Context{})

    expected = %UnaryPositiveOperator{
      value: %IntegerType{value: 2}
    }

    assert result == expected
  end
end
