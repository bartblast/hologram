defmodule Hologram.Compiler.AdditionOperatorGeneratorTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.{Context, AdditionOperatorGenerator}
  alias Hologram.Compiler.IR.{AtomType, Variable}

  test "generate/3" do
    left = %Variable{name: :x}
    right = %AtomType{value: :a}
    context = %Context{module: [], uses: [], imports: [], aliases: [], attributes: []}

    result = AdditionOperatorGenerator.generate(left, right, context)
    expected = "Kernel.$add(x, { type: 'atom', value: 'a' })"

    assert result == expected
  end
end
