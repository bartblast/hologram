defmodule Hologram.Compiler.JSEncoder.SubtractionOperatorTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, JSEncoder, Opts}
  alias Hologram.Compiler.IR.{AtomType, SubtractionOperator, Variable}

  test "encode/3" do
    ir = %SubtractionOperator{
      left: %Variable{name: :x},
      right: %AtomType{value: :a}
    }

    result = JSEncoder.encode(ir, %Context{}, %Opts{})
    expected = "Hologram.Interpreter.$subtraction_operator(x, { type: 'atom', value: 'a' })"

    assert result == expected
  end
end
