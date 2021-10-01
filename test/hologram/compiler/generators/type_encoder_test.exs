defmodule Hologram.Compiler.TypeEncoderTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, Opts, TypeEncoder}
  alias Hologram.Compiler.IR.IntegerType

  describe "encode_as_array/3" do
    test "empty" do
      data = []
      result = TypeEncoder.encode_as_array(data, %Context{}, %Opts{})

      assert result == "[]"
    end

    test "non-empty" do
      data = [%IntegerType{value: 1}, %IntegerType{value: 2}]
      result = TypeEncoder.encode_as_array(data, %Context{}, %Opts{})
      expected = "[ { type: 'integer', value: 1 }, { type: 'integer', value: 2 } ]"

      assert result == expected
    end
  end
end
