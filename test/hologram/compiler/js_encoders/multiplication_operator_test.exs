defmodule Hologram.Compiler.JSEncoder.MultiplicationOperatorTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, JSEncoder, Opts}
  alias Hologram.Compiler.IR.{AtomType, MultiplicationOperator, Variable}

  test "encode/3" do
    ir = %MultiplicationOperator{
      left: %Variable{name: :x},
      right: %AtomType{value: :a}
    }

    result = JSEncoder.encode(ir, %Context{}, %Opts{})
    expected = "Elixir_Kernel.$multiply(x, { type: 'atom', value: 'a' })"

    assert result == expected
  end
end
