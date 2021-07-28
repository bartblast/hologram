defmodule Hologram.Compiler.BinaryTypeEncoderTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.{Context, BinaryTypeEncoder}
  alias Hologram.Compiler.IR.StringType

  @context %Context{module: nil, uses: [], imports: [], aliases: [], attributes: []}
  @opts []

  test "encode/3" do
    parts = [%StringType{value: "abc"}, %StringType{value: "xyz"}]
    result = BinaryTypeEncoder.encode(parts, @context, @opts)
    expected = "{ type: 'binary', data: [ { type: 'string', value: 'abc' }, { type: 'string', value: 'xyz' } ] }"

    assert result == expected
  end
end
