defmodule Hologram.Compiler.JSEncoder.DivisionOperatorTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, JSEncoder, Opts}
  alias Hologram.Compiler.IR.{AtomType, DivisionOperator, Variable}

  test "encode/3" do
    ir = %DivisionOperator{
      left: %Variable{name: :x},
      right: %AtomType{value: :a}
    }

    result = JSEncoder.encode(ir, %Context{}, %Opts{})
    expected = "Elixir_Kernel.$divide(x, { type: 'atom', value: 'a' })"

    assert result == expected
  end
end
