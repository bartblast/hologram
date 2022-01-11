defmodule Hologram.Template.Evaluator.VariableTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR.Variable
  alias Hologram.Template.Evaluator

  @bindings %{a: 1, b: 2}

  test "evaluates the variable if binding exists" do
    ir = %Variable{name: :b}
    result = Evaluator.evaluate(ir, @bindings)

    assert result == 2
  end

  test "raises error if binding doesn't exist" do
    ir = %Variable{name: :c}

    assert_raise KeyError, "key :c not found in: %{a: 1, b: 2}", fn ->
      Evaluator.evaluate(ir, @bindings)
    end
  end
end
