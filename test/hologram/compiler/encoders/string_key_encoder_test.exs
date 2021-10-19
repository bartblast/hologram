defmodule Hologram.Compiler.StringKeyEncoderTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, MapKeyEncoder, Opts}
  alias Hologram.Compiler.IR.StringType

  test "encode/3" do
    ir = %StringType{value: "test"}

    result = MapKeyEncoder.encode(ir, %Context{}, %Opts{})
    expected = "~string[test]"

    assert result == expected
  end
end
