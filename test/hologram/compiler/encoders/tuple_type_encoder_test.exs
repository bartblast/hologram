defmodule Hologram.Compiler.TupleTypeEncoderTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, Encoder, Opts}
  alias Hologram.Compiler.IR.{IntegerType, TupleType}

  test "encode/3" do
    ir = %TupleType{
      data: [
        %IntegerType{value: 1},
        %IntegerType{value: 2}
      ]
    }

    result = Encoder.encode(ir, %Context{}, %Opts{})
    expected = "{ type: 'tuple', data: [ { type: 'integer', value: 1 }, { type: 'integer', value: 2 } ] }"

    assert result == expected
  end
end
