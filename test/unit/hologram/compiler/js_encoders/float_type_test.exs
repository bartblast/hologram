defmodule Hologram.Compiler.JSEncoder.FloatTypeTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, JSEncoder, Opts}
  alias Hologram.Compiler.IR.FloatType

  test "encode/3" do
    ir = %FloatType{value: 123.0}

    result = JSEncoder.encode(ir, %Context{}, %Opts{})
    expected = "{ type: 'float', value: 123.0 }"

    assert result == expected
  end
end
