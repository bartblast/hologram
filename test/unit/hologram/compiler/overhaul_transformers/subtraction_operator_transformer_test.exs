defmodule Hologram.Compiler.SubtractionOperatorTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR.{IntegerType, SubtractionOperator, Variable}
  alias Hologram.Compiler.SubtractionOperatorTransformer

  test "transform/3" do
    code = "a - 2"
    ast = ast(code)

    result = SubtractionOperatorTransformer.transform(ast)

    expected = %SubtractionOperator{
      left: %Variable{name: :a},
      right: %IntegerType{value: 2}
    }

    assert result == expected
  end
end
