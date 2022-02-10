defmodule Hologram.Compiler.JSEncoder.SubtractionOperatorTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, JSEncoder, Opts}
  alias Hologram.Compiler.IR.{SubtractionOperator, AtomType, Variable}

  test "encode/3" do
    ir = %SubtractionOperator{
      left: %Variable{name: :x},
      right: %AtomType{value: :a}
    }

    result = JSEncoder.encode(ir, %Context{}, %Opts{})
    expected = "Elixir_Kernel.$subtract(x, { type: 'atom', value: 'a' })"

    assert result == expected
  end
end
