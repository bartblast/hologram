defmodule Hologram.Compiler.BooleanTypeEncoderTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, Encoder, Opts}
  alias Hologram.Compiler.IR.BooleanType

  test "encode/3" do
    ir = %BooleanType{value: true}

    result = Encoder.encode(ir, %Context{}, %Opts{})
    expected = "{ type: 'boolean', value: true }"

    assert result == expected
  end
end
