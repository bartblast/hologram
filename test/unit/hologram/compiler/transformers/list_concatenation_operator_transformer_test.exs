defmodule Hologram.Compiler.ListConcatenationOperatorTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, ListConcatenationOperatorTransformer}
  alias Hologram.Compiler.IR.{IntegerType, ListConcatenationOperator, ListType}

  test "transform/3" do
    code = "[1, 2] ++ [3, 4]"
    ast = ast(code)

    result = ListConcatenationOperatorTransformer.transform(ast, %Context{})

    expected = %ListConcatenationOperator{
      left: %ListType{
        data: [
          %IntegerType{value: 1},
          %IntegerType{value: 2}
        ]
      },
      right: %ListType{
        data: [
          %IntegerType{value: 3},
          %IntegerType{value: 4}
        ]
      }
    }

    assert result == expected
  end
end
