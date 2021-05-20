defmodule Hologram.Template.EvaluatorTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.IR.ModuleAttributeOperator
  alias Hologram.Template.Evaluator

  test "module attribute" do
    state = %{a: 123}
    ir = %ModuleAttributeOperator{name: :a}

    result = Evaluator.evaluate(ir, state)
    expected = 123

    assert result == expected
  end
end
