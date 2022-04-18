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
    Elixir_Kernel.if(() => {
    return { type: 'boolean', value: true };
    }, () => {
    return { type: 'integer', value: 1 };
    }, () => {
    return { type: 'integer', value: 2 };
    })\
    """

    assert result == expected
  end
end
