defmodule Hologram.Compiler.JSEncoder.ListTypeTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, JSEncoder, Opts}
  alias Hologram.Compiler.IR.{IntegerType, ListType}

  test "encode/3" do
    ir = %ListType{
      data: [
        %IntegerType{value: 1},
        %IntegerType{value: 2}
      ]
    }

    result = JSEncoder.encode(ir, %Context{}, %Opts{})

    expected =
      "{ type: 'list', data: [ { type: 'integer', value: 1 }, { type: 'integer', value: 2 } ] }"

    assert result == expected
  end
end
