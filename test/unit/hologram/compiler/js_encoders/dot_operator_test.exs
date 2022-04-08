defmodule Hologram.Compiler.JSEncoder.DotOperatorTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, JSEncoder, Opts}
  alias Hologram.Compiler.IR.{AtomType, DotOperator, Variable}

  test "encode/3" do
    ir = %DotOperator{
      left: %Variable{name: :x},
      right: %AtomType{value: :a}
    }

    result = JSEncoder.encode(ir, %Context{}, %Opts{})
    expected = "Hologram.Interpreter.$dot_operator(x, { type: 'atom', value: 'a' })"

    assert result == expected
  end
end
