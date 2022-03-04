defmodule Hologram.Compiler.JSEncoder.UnaryNegativeOperatorTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, JSEncoder, Opts}
  alias Hologram.Compiler.IR.{IntegerType, UnaryNegativeOperator}

  test "encode/3" do
    ir = %UnaryNegativeOperator{
      value: %IntegerType{value: 123}
    }

    result = JSEncoder.encode(ir, %Context{}, %Opts{})
    expected = "Elixir_Kernel.$unary_negative({ type: 'integer', value: 123 })"

    assert result == expected
  end
end
