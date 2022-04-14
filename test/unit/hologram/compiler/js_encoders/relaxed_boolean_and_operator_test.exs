defmodule Hologram.Compiler.JSEncoder.RelaxedBooleanAndOperatorTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, JSEncoder, Opts}
  alias Hologram.Compiler.IR.{IntegerType, RelaxedBooleanAndOperator}

  test "encode/3" do
    ir = %RelaxedBooleanAndOperator{
      left: %IntegerType{value: 1},
      right: %IntegerType{value: 2}
    }

    result = JSEncoder.encode(ir, %Context{}, %Opts{})

    expected =
      "Hologram.Interpreter.$relaxed_boolean_and_operator({ type: 'integer', value: 1 }, { type: 'integer', value: 2 })"

    assert result == expected
  end
end
