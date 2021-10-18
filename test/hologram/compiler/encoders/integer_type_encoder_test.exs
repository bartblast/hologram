defmodule Hologram.Compiler.IntegerTypeEncoderTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, Encoder, Opts}
  alias Hologram.Compiler.IR.IntegerType

  test "encode/3" do
    ir = %IntegerType{value: 123}

    result = Encoder.encode(ir, %Context{}, %Opts{})
    expected = "{ type: 'integer', value: 123 }"

    assert result == expected
  end
end
