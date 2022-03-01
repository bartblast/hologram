defmodule Hologram.Compiler.EvaluatorTest do
  use Hologram.Test.UnitCase, async: true
  alias Hologram.Compiler.Evaluator

  @bindings %{a: 1, b: 2, c: 3}

  test "evaluates addition expression" do
    code = "1 + @a + @c"
    ast = ast(code)
    result = Evaluator.evaluate(ast, @bindings)

    assert result == 5
  end

  test "evaluated if expression" do
    code = "if @a, do: @b, else: @c"
    ast = ast(code)
    result = Evaluator.evaluate(ast, @bindings)

    assert result == 2
  end

  test "injects bindings key into bindings" do
    code = "1 + @bindings.c"
    ast = ast(code)
    result = Evaluator.evaluate(ast, @bindings)

    assert result == 4
  end
end
