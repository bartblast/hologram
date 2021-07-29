defmodule Hologram.Compiler.BinaryTypeEncoderTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.{Context, BinaryTypeEncoder}
  alias Hologram.Compiler.IR.StringType

  @opts []

  test "encode/3" do
    parts = [%StringType{value: "abc"}, %StringType{value: "xyz"}]
    result = BinaryTypeEncoder.encode(parts, %Context{}, @opts)
    expected = "{ type: 'binary', data: [ { type: 'string', value: 'abc' }, { type: 'string', value: 'xyz' } ] }"

    assert result == expected
  end
end
