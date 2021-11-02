defmodule Hologram.Compiler.JSEncoder.BooleanTypeTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, JSEncoder, Opts}
  alias Hologram.Compiler.IR.BooleanType

  test "encode/3" do
    ir = %BooleanType{value: true}

    result = JSEncoder.encode(ir, %Context{}, %Opts{})
    expected = "{ type: 'boolean', value: true }"

    assert result == expected
  end
end
