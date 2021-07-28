defmodule Hologram.Compiler.TypeEncoderTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.{Context, TypeEncoder}
  alias Hologram.Compiler.IR.IntegerType

  @context %Context{module: nil, uses: [], imports: [], aliases: [], attributes: []}
  @opts []

  describe "encode_as_list/3" do
    test "empty" do
      data = []
      result = TypeEncoder.encode_as_list(data, @context, @opts)

      assert result == "[]"
    end

    test "non-empty" do
      data = [%IntegerType{value: 1}, %IntegerType{value: 2}]
      result = TypeEncoder.encode_as_list(data, @context, @opts)
      expected = "[ { type: 'integer', value: 1 }, { type: 'integer', value: 2 } ]"

      assert result == expected
    end
  end
end
