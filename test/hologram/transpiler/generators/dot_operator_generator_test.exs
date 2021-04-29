defmodule Hologram.Transpiler.DotOperatorGeneratorTest do
  use ExUnit.Case, async: true

  alias Hologram.Transpiler.AST.{AtomType, Variable}
  alias Hologram.Transpiler.DotOperatorGenerator

  test "generate/2" do
    left = %Variable{name: :x}
    right = %AtomType{value: :a}

    result = DotOperatorGenerator.generate(left, right)

    expected =
      "Kernel.dot_operator({ type: 'variable', name: 'x' }, { type: 'atom', value: 'a' })"

    assert result == expected
  end
end
