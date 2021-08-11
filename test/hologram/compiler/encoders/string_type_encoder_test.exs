defmodule Hologram.Compiler.StrintTypeEncoderTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.{Context, Encoder, Opts}
  alias Hologram.Compiler.IR.StringType

  test "encode/3" do
    ir = %StringType{value: "abc'bcd"}

    result = Encoder.encode(ir, %Context{}, %Opts{})
    expected = "{ type: 'string', value: 'abc\\'bcd' }"

    assert result == expected
  end
end
