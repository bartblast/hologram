defmodule Hologram.Compiler.DotOperatorEncoderTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, Encoder, Opts}
  alias Hologram.Compiler.IR.{AtomType, DotOperator, Variable}

  test "encode/3" do
    ir = %DotOperator{
      left: %Variable{name: :x},
      right: %AtomType{value: :a}
    }

    result = Encoder.encode(ir, %Context{}, %Opts{})
    expected = "Elixir_Kernel_SpecialForms.$dot(x, { type: 'atom', value: 'a' })"

    assert result == expected
  end
end
