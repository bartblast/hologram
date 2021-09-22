defmodule Hologram.Compiler.TypeOperatorEncoderTest do
  use Hologram.Test.UnitCase , async: true

  alias Hologram.Compiler.{Context, Opts, TypeOperatorEncoder}
  alias Hologram.Compiler.IR.IntegerType

  test "encode/4" do
    left = %IntegerType{value: 1}
    right = :binary

    result = TypeOperatorEncoder.encode(left, right, %Context{}, %Opts{})
    expected = "Elixir.typeOperator({ type: 'integer', value: 1 }, 'binary')"

    assert result == expected
  end
end
