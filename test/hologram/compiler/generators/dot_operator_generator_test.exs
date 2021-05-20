defmodule Hologram.Compiler.DotOperatorGeneratorTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.IR.{AtomType, Variable}
  alias Hologram.Compiler.DotOperatorGenerator

  test "generate/2" do
    left = %Variable{name: :x}
    right = %AtomType{value: :a}

    result = DotOperatorGenerator.generate(left, right, [])

    expected =
      "Kernel.$dot(x, { type: 'atom', value: 'a' })"

    assert result == expected
  end
end
