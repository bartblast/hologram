defmodule Hologram.Compiler.JSEncoder.RelaxedBooleanNotOperatorTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, JSEncoder, Opts}
  alias Hologram.Compiler.IR.{BooleanType, RelaxedBooleanNotOperator}

  test "encode/3" do
    ir = %RelaxedBooleanNotOperator{
      value: %BooleanType{value: false}
    }

    result = JSEncoder.encode(ir, %Context{}, %Opts{})

    expected =
      "Hologram.Interpreter.$relaxed_boolean_not_operator({ type: 'boolean', value: false })"

    assert result == expected
  end
end
