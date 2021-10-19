defmodule Hologram.Compiler.ModuleTypeEncoderTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, Encoder, Opts}
  alias Hologram.Compiler.IR.ModuleType

  test "encode/3" do
    ir = %ModuleType{module: Abc.Bcd}

    result = Encoder.encode(ir, %Context{}, %Opts{})
    expected = "{ type: 'module', className: 'Elixir_Abc_Bcd' }"

    assert result == expected
  end
end
