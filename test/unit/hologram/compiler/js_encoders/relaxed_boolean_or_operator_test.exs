defmodule Hologram.Compiler.JSEncoder.RelaxedBooleanOrOperatorTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, JSEncoder, Opts}
  alias Hologram.Compiler.IR.{IntegerType, RelaxedBooleanOrOperator}

  test "encode/3" do
    ir = %RelaxedBooleanOrOperator{
      left: %IntegerType{value: 1},
      right: %IntegerType{value: 2}
    }

    result = JSEncoder.encode(ir, %Context{}, %Opts{})

    expected =
      "Hologram.Interpreter.$relaxed_boolean_or_operator({ type: 'integer', value: 1 }, { type: 'integer', value: 2 })"

    assert result == expected
  end
end
