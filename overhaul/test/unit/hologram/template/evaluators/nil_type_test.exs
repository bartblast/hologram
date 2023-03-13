defmodule Hologram.Template.Evaluator.NilTypeTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR.NilType
  alias Hologram.Template.Evaluator

  test "evaluate/2" do
    ir = %NilType{}

    result = Evaluator.evaluate(ir, %{})
    expected = nil

    assert result == expected
  end
end
