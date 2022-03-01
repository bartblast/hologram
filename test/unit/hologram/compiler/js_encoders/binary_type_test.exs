defmodule Hologram.Compiler.JSEncoder.BinaryTypeTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, JSEncoder, Opts}
  alias Hologram.Compiler.IR.{BinaryType, StringType}

  test "encode/3" do
    ir = %BinaryType{
      parts: [
        %StringType{value: "abc"},
        %StringType{value: "xyz"}
      ]
    }

    result = JSEncoder.encode(ir, %Context{}, %Opts{})

    expected =
      "{ type: 'binary', data: [ { type: 'string', value: 'abc' }, { type: 'string', value: 'xyz' } ] }"

    assert result == expected
  end
end
