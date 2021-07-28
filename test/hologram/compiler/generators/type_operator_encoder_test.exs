defmodule Hologram.Compiler.TypeOperatorEncoderTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.{Context, TypeOperatorEncoder}
  alias Hologram.Compiler.IR.IntegerType

  @context %Context{module: nil, uses: [], imports: [], aliases: [], attributes: []}
  @opts []

  test "encode/4" do
    left = %IntegerType{value: 1}
    right = :binary

    result = TypeOperatorEncoder.encode(left, right, @context, @opts)
    expected = "Elixir.typeOperator({ type: 'integer', value: 1 }, 'binary')"

    assert result == expected
  end
end
