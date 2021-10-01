defmodule Hologram.Compiler.NilTypeEncoderTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, Encoder, Opts}
  alias Hologram.Compiler.IR.NilType

  test "encode/3" do
    ir = %NilType{}

    result = Encoder.encode(ir, %Context{}, %Opts{})
    expected = "{ type: 'nil' }"

    assert result == expected
  end
end
