defmodule Hologram.Compiler.TypeOperatorEncoderTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, Encoder, Opts}
  alias Hologram.Compiler.IR.{IntegerType, TypeOperator}

  test "encode/3" do
    ir = %TypeOperator{
      left: %IntegerType{value: 1},
      right: :binary
    }

    result = Encoder.encode(ir, %Context{}, %Opts{})
    expected = "Elixir_Kernel_SpecialForms.$type({ type: 'integer', value: 1 }, 'binary')"

    assert result == expected
  end
end
