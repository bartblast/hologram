defmodule Hologram.Compiler.DotOperatorGeneratorTest do
  use ExUnit.Case, async: true

  alias Hologram.Compiler.AST.{AtomType, Variable}
  alias Hologram.Compiler.DotOperatorGenerator

  test "generate/2" do
    left = %Variable{name: :x}
    right = %AtomType{value: :a}

    result = DotOperatorGenerator.generate(left, right, [])

    expected =
      "Kernel.dot_operator(x, { type: 'atom', value: 'a' })"

    assert result == expected
  end
end
