defmodule Hologram.Transpiler.AdditionOperatorGeneratorTest do
  use ExUnit.Case, async: true

  alias Hologram.Transpiler.AST.{AtomType, Variable}
  alias Hologram.Transpiler.AdditionOperatorGenerator

  test "generate/2" do
    left = %Variable{name: :x}
    right = %AtomType{value: :a}

    result = AdditionOperatorGenerator.generate(left, right, [])

    expected =
      "Kernel.additionOperator(x, { type: 'atom', value: 'a' })"

    assert result == expected
  end
end
