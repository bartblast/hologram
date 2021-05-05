defmodule Hologram.Compiler.AdditionOperatorGeneratorTest do
  use ExUnit.Case, async: true

  alias Hologram.Compiler.AST.{AtomType, Variable}
  alias Hologram.Compiler.AdditionOperatorGenerator

  test "generate/3" do
    left = %Variable{name: :x}
    right = %AtomType{value: :a}

    result = AdditionOperatorGenerator.generate(left, right, [])

    expected =
      "Kernel.addition_operator(x, { type: 'atom', value: 'a' })"

    assert result == expected
  end
end
