defmodule Hologram.Compiler.JSEncoder.IntegerTypeTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, JSEncoder, Opts}
  alias Hologram.Compiler.IR.IntegerType

  test "encode/3" do
    ir = %IntegerType{value: 123}

    result = JSEncoder.encode(ir, %Context{}, %Opts{})
    expected = "{ type: 'integer', value: 123 }"

    assert result == expected
  end
end
