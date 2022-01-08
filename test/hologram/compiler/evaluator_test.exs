defmodule Hologram.Compiler.EvaluatorTest do
  use Hologram.Test.UnitCase, async: true
  alias Hologram.Compiler.Evaluator

  test "evaluate/2" do
    bindings = %{a: 2, b: 10}
    code = "1 + @a + @b"
    ast = ast(code)
    result = Evaluator.evaluate(ast, bindings)

    assert result == 13
  end
end
