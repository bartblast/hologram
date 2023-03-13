defmodule Hologram.Template.Evaluator.IfExpressionTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, Transformer}
  alias Hologram.Template.Evaluator

  test "evaluate/2" do
    bindings = %{a: 1, b: 2, c: 3}
    code = "if @a, do: @b, else: @c"
    ast = ast(code)
    ir = Transformer.transform(ast, %Context{})
    result = Evaluator.evaluate(ir, bindings)

    assert result == 2
  end
end
