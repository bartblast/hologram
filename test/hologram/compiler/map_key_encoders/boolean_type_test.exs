defmodule Hologram.Compiler.MapKeyEncoder.BooleanTypeTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, MapKeyEncoder, Opts}
  alias Hologram.Compiler.IR.BooleanType

  test "encode/3" do
    ir = %BooleanType{value: true}

    result = MapKeyEncoder.encode(ir, %Context{}, %Opts{})
    expected = "~boolean[true]"

    assert result == expected
  end
end
