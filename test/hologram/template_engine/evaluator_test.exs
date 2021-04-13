defmodule Hologram.TemplateEngine.EvaluatorTest do
  use ExUnit.Case, async: true

  alias Hologram.TemplateEngine.Evaluator
  alias Hologram.Transpiler.AST.ModuleAttribute

  test "module attribute" do
    state = %{a: 123}
    ast = %ModuleAttribute{name: :a}

    result = Evaluator.evaluate(ast, state)
    expected = "123"

    assert result == expected
  end
end
