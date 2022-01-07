defmodule Hologram.Template.Evaluator.VariableTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR.Variable
  alias Hologram.Template.Evaluator

  test "evaluate/2" do
    bindings = %{a: 1, b: 2}
    ir = %Variable{name: :b}
    result = Evaluator.evaluate(ir, bindings)

    assert result == 2
  end
end
