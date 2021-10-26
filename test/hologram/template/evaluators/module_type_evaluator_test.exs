defmodule Hologram.Template.ModuleTypeEvaluatorTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR.ModuleType
  alias Hologram.Template.Evaluator

  test "evaluate/2" do
    ir = %ModuleType{module: Hologram.Template.ModuleTypeEvaluatorTest}

    result = Evaluator.evaluate(ir, %{})
    expected = Hologram.Template.ModuleTypeEvaluatorTest

    assert result == expected
  end
end
