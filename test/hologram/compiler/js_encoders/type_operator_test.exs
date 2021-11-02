defmodule Hologram.Compiler.JSEncoder.TypeOperatorTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, JSEncoder, Opts}
  alias Hologram.Compiler.IR.{IntegerType, TypeOperator}

  test "encode/3" do
    ir = %TypeOperator{
      left: %IntegerType{value: 1},
      right: :binary
    }

    result = JSEncoder.encode(ir, %Context{}, %Opts{})
    expected = "Elixir_Kernel_SpecialForms.$type({ type: 'integer', value: 1 }, 'binary')"

    assert result == expected
  end
end
