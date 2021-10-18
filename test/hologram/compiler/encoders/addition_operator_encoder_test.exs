defmodule Hologram.Compiler.AdditionOperatorEncoderTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, Encoder, Opts}
  alias Hologram.Compiler.IR.{AdditionOperator, AtomType, Variable}

  test "encode/3" do
    ir = %AdditionOperator{
      left: %Variable{name: :x},
      right: %AtomType{value: :a}
    }

    result = Encoder.encode(ir, %Context{}, %Opts{})
    expected = "Elixir_Kernel.$add(x, { type: 'atom', value: 'a' })"

    assert result == expected
  end
end
