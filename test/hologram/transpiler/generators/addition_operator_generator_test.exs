defmodule Hologram.Transpiler.AdditionOperatorGeneratorTest do
  use ExUnit.Case, async: true

  alias Hologram.Transpiler.AST.{AtomType, Variable}
  alias Hologram.Transpiler.AdditionOperatorGenerator

  test "generate/2" do
    left = %Variable{name: :x}
    right = %AtomType{value: :a}
    context = [module_attributes: []]

    result = AdditionOperatorGenerator.generate(left, right, context)

    expected =
      "Kernel.additionOperator(x, { type: 'atom', value: 'a' })"

    assert result == expected
  end
end
