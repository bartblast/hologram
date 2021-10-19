defmodule Hologram.Compiler.IntegerKeyEncoderTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, MapKeyEncoder, Opts}
  alias Hologram.Compiler.IR.IntegerType

  test "encode/3" do
    ir = %IntegerType{value: 123}

    result = MapKeyEncoder.encode(ir, %Context{}, %Opts{})
    expected = "~integer[123]"

    assert result == expected
  end
end
