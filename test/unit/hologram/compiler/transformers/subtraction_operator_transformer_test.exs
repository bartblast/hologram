defmodule Hologram.Compiler.SubtractionOperatorTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, SubtractionOperatorTransformer}
  alias Hologram.Compiler.IR.{IntegerType, SubtractionOperator, Variable}

  test "transform/3" do
    code = "a - 2"
    ast = ast(code)

    result = SubtractionOperatorTransformer.transform(ast, %Context{})

    expected = %SubtractionOperator{
      left: %Variable{name: :a},
      right: %IntegerType{value: 2}
    }

    assert result == expected
  end
end
