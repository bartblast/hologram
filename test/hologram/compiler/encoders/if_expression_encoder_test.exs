defmodule Hologram.Compiler.IfExpressionEncoderTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, Encoder, Opts}
  alias Hologram.Compiler.IR.{BooleanType, IfExpression, IntegerType}

  test "encode/3" do
    ir = %IfExpression{
      condition: %BooleanType{value: true},
      do: [%IntegerType{value: 1}],
      else: [%IntegerType{value: 2}]
    }

    result = Encoder.encode(ir, %Context{}, %Opts{})

    expected =
      "Elixir_Kernel.if((function() { return { type: 'boolean', value: true }; }), (function() { return { type: 'integer', value: 1 }; }), (function() { return { type: 'integer', value: 2 }; }))"

    assert result == expected
  end
end
