defmodule Hologram.Compiler.JSEncoder.TupleTypeTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, JSEncoder, Opts}
  alias Hologram.Compiler.IR.{IntegerType, TupleType}

  test "encode/3" do
    ir = %TupleType{
      data: [
        %IntegerType{value: 1},
        %IntegerType{value: 2}
      ]
    }

    result = JSEncoder.encode(ir, %Context{}, %Opts{})
    expected = "{ type: 'tuple', data: [ { type: 'integer', value: 1 }, { type: 'integer', value: 2 } ] }"

    assert result == expected
  end
end
