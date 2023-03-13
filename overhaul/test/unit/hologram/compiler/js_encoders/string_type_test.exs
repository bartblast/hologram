defmodule Hologram.Compiler.JSEncoder.StringTypeTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, JSEncoder, Opts}
  alias Hologram.Compiler.IR.StringType

  test "encode/3" do
    ir = %StringType{value: "abc'bcd\ncde"}

    result = JSEncoder.encode(ir, %Context{}, %Opts{})
    expected = "{ type: 'string', value: 'abc\\'bcd\\ncde' }"

    assert result == expected
  end
end
