defmodule Hologram.Template.Evaluator.StringTypeTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR.StringType
  alias Hologram.Template.Evaluator

  test "evaluate/2" do
    ir = %StringType{value: "abc"}

    result = Evaluator.evaluate(ir, %{})
    expected = "abc"

    assert result == expected
  end
end
