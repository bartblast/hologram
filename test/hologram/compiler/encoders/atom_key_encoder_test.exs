defmodule Hologram.Compiler.AtomKeyEncoderTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, MapKeyEncoder, Opts}
  alias Hologram.Compiler.IR.AtomType

  test "encode/3" do
    ir = %AtomType{value: :test}

    result = MapKeyEncoder.encode(ir, %Context{}, %Opts{})
    expected = "~atom[test]"

    assert result == expected
  end
end
