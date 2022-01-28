defmodule Hologram.Compiler.JSEncoder.UnaryPositiveOperatorTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, JSEncoder, Opts}
  alias Hologram.Compiler.IR.{IntegerType, UnaryPositiveOperator}

  test "encode/3" do
    ir = %UnaryPositiveOperator{
      value: %IntegerType{value: 123},
    }

    result = JSEncoder.encode(ir, %Context{}, %Opts{})
    expected = "{ type: 'integer', value: 123 }"

    assert result == expected
  end
end
