defmodule Hologram.Template.ModuleAttributeOperatorEvaluatorTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.IR.ModuleAttributeOperator
  alias Hologram.Template.Evaluator

  test "evaluate/2" do
    ir = %ModuleAttributeOperator{name: :a}
    state = %{a: 123}

    result = Evaluator.evaluate(ir, state)
    expected = 123

    assert result == expected
  end
end
