defmodule Hologram.Compiler.IfExpressionTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, IfExpressionTransformer}
  alias Hologram.Compiler.IR.{Block, BooleanType, IfExpression, IntegerType}

  test "transform/2" do
    code = """
    if true do
      1
      2
    else
      3
      4
    end
    """

    ast = ast(code)
    result = IfExpressionTransformer.transform(ast, %Context{})

    expected = %IfExpression{
      condition: %BooleanType{value: true},
      do: %Block{
        expressions: [
          %IntegerType{value: 1},
          %IntegerType{value: 2}
        ]
      },
      else: %Block{
        expressions: [
          %IntegerType{value: 3},
          %IntegerType{value: 4}
        ]
      },
      ast: ast
    }

    assert result == expected
  end
end
