defmodule Hologram.Compiler.JSEncoder.IfExpressionTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, JSEncoder, Opts}
  alias Hologram.Compiler.IR.{Block, BooleanType, IfExpression, IntegerType}

  test "encode/3" do
    ir = %IfExpression{
      condition: %BooleanType{value: true},
      do: %Block{expressions: [%IntegerType{value: 1}]},
      else: %Block{expressions: [%IntegerType{value: 2}]}
    }

    result = JSEncoder.encode(ir, %Context{}, %Opts{})

    expected = """
    Elixir_Kernel.if(function() {
    return { type: 'boolean', value: true };
    }, function() {
    return { type: 'integer', value: 1 };
    }, function() {
    return { type: 'integer', value: 2 };
    })\
    """

    assert result == expected
  end
end
