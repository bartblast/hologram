defmodule Hologram.Template.ExpressionGeneratorTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.IR.{AtomType, TupleType}
  alias Hologram.Template.ExpressionGenerator

  test "generate/2" do
    ir = %TupleType{
      data: [%AtomType{value: "x"}]
    }
    
    result = ExpressionGenerator.generate(ir)

    expected =
      "{ type: 'expression', callback: ($state) => { return { type: 'atom', value: 'x' } } }"

    assert result == expected
  end
end
