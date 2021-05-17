defmodule Hologram.Template.EvaluatorTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.AST.ModuleAttributeOperator
  alias Hologram.Template.Evaluator

  test "module attribute" do
    state = %{a: 123}
    ast = %ModuleAttributeOperator{name: :a}

    result = Evaluator.evaluate(ast, state)
    expected = 123

    assert result == expected
  end
end
