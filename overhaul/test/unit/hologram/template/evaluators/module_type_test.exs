defmodule Hologram.Template.Evaluator.ModuleTypeTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR.ModuleType
  alias Hologram.Template.Evaluator

  test "evaluate/2" do
    ir = %ModuleType{module: Hologram.Template.Evaluator.ModuleTypeTest}

    result = Evaluator.evaluate(ir, %{})
    expected = Hologram.Template.Evaluator.ModuleTypeTest

    assert result == expected
  end
end
