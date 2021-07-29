defmodule Hologram.Compiler.AdditionOperatorGeneratorTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.{Context, AdditionOperatorGenerator}
  alias Hologram.Compiler.IR.{AtomType, Variable}

  test "generate/3" do
    left = %Variable{name: :x}
    right = %AtomType{value: :a}

    result = AdditionOperatorGenerator.generate(left, right, %Context{})
    expected = "Elixir_Kernel.$add(x, { type: 'atom', value: 'a' })"

    assert result == expected
  end
end
