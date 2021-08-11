defmodule Hologram.Compiler.StrintTypeEncoderTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.{Context, Encoder, Opts}
  alias Hologram.Compiler.IR.StringType

  test "encode/3" do
    ir = %StringType{value: "abc'bcd\ncde"}

    result = Encoder.encode(ir, %Context{}, %Opts{})
    expected = "{ type: 'string', value: 'abc\\'bcd\\ncde' }"

    assert result == expected
  end
end
