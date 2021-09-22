defmodule Hologram.Template.AtomTypeEvaluatorTest do
  use Hologram.Test.UnitCase , async: true

  alias Hologram.Compiler.IR.AtomType
  alias Hologram.Template.Evaluator

  test "evaluate/2" do
    ir = %AtomType{value: :a}

    result = Evaluator.evaluate(ir, %{})
    expected = :a

    assert result == expected
  end
end
