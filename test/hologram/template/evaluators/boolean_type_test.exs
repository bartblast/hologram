defmodule Hologram.Template.Evaluator.BooleanTypeTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR.BooleanType
  alias Hologram.Template.Evaluator

  test "evaluate/2" do
    ir = %BooleanType{value: true}

    result = Evaluator.evaluate(ir, %{})
    expected = true

    assert result == expected
  end
end
