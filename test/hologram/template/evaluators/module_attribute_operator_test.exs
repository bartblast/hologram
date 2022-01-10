defmodule Hologram.Template.Evaluator.ModuleAttributeOperatorTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR.ModuleAttributeOperator
  alias Hologram.Template.Evaluator

  @bindings %{a: 123}

  test "existing binding" do
    ir = %ModuleAttributeOperator{name: :a}
    result = Evaluator.evaluate(ir, @bindings)

    assert result == 123
  end

  test "non-existing binding" do
    ir = %ModuleAttributeOperator{name: :b}

    assert_raise KeyError, "key :b not found in: %{a: 123}", fn ->
      Evaluator.evaluate(ir, @bindings)
    end
  end
end
