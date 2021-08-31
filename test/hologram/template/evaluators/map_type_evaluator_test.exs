defmodule Hologram.Template.MapTypeEvaluatorTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.IR.{AtomType, IntegerType, MapType}
  alias Hologram.Template.Evaluator

  test "evaluate/2" do
    ir = %MapType{
      data: [
        {%AtomType{value: :a}, %IntegerType{value: 1}},
        {%AtomType{value: :b}, %IntegerType{value: 2}}
      ]
    }

    result = Evaluator.evaluate(ir, %{})
    expected = %{a: 1, b: 2}

    assert result == expected
  end
end
