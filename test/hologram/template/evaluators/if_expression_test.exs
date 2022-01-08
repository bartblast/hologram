defmodule Hologram.Template.Evaluator.IfExpressionTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, Transformer}
  alias Hologram.Template.Evaluator

  test "evaluate/2" do
    bindings = %{a: 1, b: 2}
    code = "if true, do: a, else: b"
    ast = ast(code)
    ir = Transformer.transform(ast, %Context{})
    result = Evaluator.evaluate(ir, %{a: 123, b: 234})

    assert result == 123
  end
end
