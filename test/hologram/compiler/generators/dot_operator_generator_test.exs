defmodule Hologram.Compiler.DotOperatorGeneratorTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.{Context, DotOperatorGenerator}
  alias Hologram.Compiler.IR.{AtomType, Variable}

  test "generate/2" do
    left = %Variable{name: :x}
    right = %AtomType{value: :a}
    context = %Context{module: nil, uses: [], imports: [], aliases: [], attributes: []}

    result = DotOperatorGenerator.generate(left, right, context)
    expected = "Elixir_Kernel.$dot(x, { type: 'atom', value: 'a' })"

    assert result == expected
  end
end
