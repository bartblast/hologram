defmodule Hologram.Compiler.EvaluatorTest do
  use Hologram.Test.UnitCase, async: true
  alias Hologram.Compiler.Evaluator

  @bindings %{a: 1, b: 2, c: 3}

  test "evaluates addition expression" do
    code = "1 + @a + @b"
    ast = ast(code)
    result = Evaluator.evaluate(ast, @bindings)

    assert result == 4
  end

  test "evaluated if expression" do
    code = "if @a, do: @b, else: @c"
    ast = ast(code)
    result = Evaluator.evaluate(ast, @bindings)

    assert result == 2
  end
end
