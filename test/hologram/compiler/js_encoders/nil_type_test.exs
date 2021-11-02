defmodule Hologram.Compiler.JSEncoder.NilTypeTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, JSEncoder, Opts}
  alias Hologram.Compiler.IR.NilType

  test "encode/3" do
    ir = %NilType{}

    result = JSEncoder.encode(ir, %Context{}, %Opts{})
    expected = "{ type: 'nil' }"

    assert result == expected
  end
end
