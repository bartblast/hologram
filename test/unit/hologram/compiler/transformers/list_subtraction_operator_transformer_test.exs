defmodule Hologram.Compiler.ListSubtractionOperatorTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, ListSubtractionOperatorTransformer}
  alias Hologram.Compiler.IR.{IntegerType, ListSubtractionOperator, ListType}

  test "transform/3" do
    code = "[1, 2] -- [3, 2]"
    ast = ast(code)

    result = ListSubtractionOperatorTransformer.transform(ast, %Context{})

    expected = %ListSubtractionOperator{
      left: %ListType{
        data: [
          %IntegerType{value: 1},
          %IntegerType{value: 2}
        ]
      },
      right: %ListType{
        data: [
          %IntegerType{value: 3},
          %IntegerType{value: 2}
        ]
      }
    }

    assert result == expected
  end
end
