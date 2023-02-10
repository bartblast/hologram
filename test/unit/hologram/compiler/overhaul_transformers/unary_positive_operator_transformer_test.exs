defmodule Hologram.Compiler.UnaryPositiveOperatorTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR.IntegerType
  alias Hologram.Compiler.IR.UnaryPositiveOperator
  alias Hologram.Compiler.UnaryPositiveOperatorTransformer

  test "transform/3" do
    code = "+2"
    ast = ast(code)

    result = UnaryPositiveOperatorTransformer.transform(ast)

    expected = %UnaryPositiveOperator{
      value: %IntegerType{value: 2}
    }

    assert result == expected
  end
end
