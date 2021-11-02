defmodule Hologram.Template.ExpressionEncoderTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR.{AtomType, TupleType}
  alias Hologram.Template.VDOM.Expression
  alias Hologram.Template.Encoder

  test "encode/1" do
    expression = %Expression{
      ir: %TupleType{
        data: [%AtomType{value: "x"}]
      }
    }

    result = Encoder.encode(expression)

    expected =
      "{ type: 'expression', callback: ($bindings) => { return { type: 'tuple', data: [ { type: 'atom', value: 'x' } ] } } }"

    assert result == expected
  end
end
