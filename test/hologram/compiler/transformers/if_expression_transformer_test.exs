defmodule Hologram.Compiler.IfExpressionTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, IfExpressionTransformer}
  alias Hologram.Compiler.IR.{BooleanType, IfExpression, IntegerType, NilType}

  @context %Context{}

  test "do clause with single expression" do
    code = "if true, do: 1"
    ast = ast(code)
    result = IfExpressionTransformer.transform(ast, @context)

    expected = %IfExpression{
      condition: %BooleanType{value: true},
      do: [%IntegerType{value: 1}],
      else: [%NilType{}],
      ast: ast,
      context: @context
    }

    assert result == expected
  end

  test "do clause with multiple expressions" do
    code = """
    if true do
      1
      2
    end
    """

    ast = ast(code)
    result = IfExpressionTransformer.transform(ast, @context)

    expected = %IfExpression{
      condition: %BooleanType{value: true},
      do: [
        %IntegerType{value: 1},
        %IntegerType{value: 2}
      ],
      else: [%NilType{}],
      ast: ast,
      context: @context
    }

    assert result == expected
  end

  test "do clause with single expression and else clause with single expression" do
    code = "if true, do: 1, else: 2"
    ast = ast(code)
    result = IfExpressionTransformer.transform(ast, @context)

    expected = %IfExpression{
      condition: %BooleanType{value: true},
      do: [%IntegerType{value: 1}],
      else: [%IntegerType{value: 2}],
      ast: ast,
      context: @context
    }

    assert result == expected
  end

  test "do clause with multiple expressions and else clause with single expression" do
    code = """
    if true do
      1
      2
    else
      3
    end
    """

    ast = ast(code)
    result = IfExpressionTransformer.transform(ast, @context)

    expected = %IfExpression{
      condition: %BooleanType{value: true},
      do: [
        %IntegerType{value: 1},
        %IntegerType{value: 2}
      ],
      else: [%IntegerType{value: 3}],
      ast: ast,
      context: @context
    }

    assert result == expected
  end

  test "do clause with multiple expressions and else clause with multiple expressions" do
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
    result = IfExpressionTransformer.transform(ast, @context)

    expected = %IfExpression{
      condition: %BooleanType{value: true},
      do: [
        %IntegerType{value: 1},
        %IntegerType{value: 2}
      ],
      else: [
        %IntegerType{value: 3},
        %IntegerType{value: 4}
      ],
      ast: ast,
      context: @context
    }

    assert result == expected
  end
end
