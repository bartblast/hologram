defmodule Hologram.Compiler.JSEncoder.AdditionOperatorTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, JSEncoder, Opts}
  alias Hologram.Compiler.IR.{AdditionOperator, AtomType, Variable}

  test "encode/3" do
    ir = %AdditionOperator{
      left: %Variable{name: :x},
      right: %AtomType{value: :a}
    }

    result = JSEncoder.encode(ir, %Context{}, %Opts{})
    expected = "Hologram.Interpreter.$addition_operator(x, { type: 'atom', value: 'a' })"

    assert result == expected
  end
end
