defmodule Hologram.Compiler.JSEncoder.LessThanOperatorTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.Context
  alias Hologram.Compiler.IR.IntegerType
  alias Hologram.Compiler.IR.LessThanOperator
  alias Hologram.Compiler.JSEncoder
  alias Hologram.Compiler.Opts

  test "encode/3" do
    ir = %LessThanOperator{
      left: %IntegerType{value: 1},
      right: %IntegerType{value: 2}
    }

    result = JSEncoder.encode(ir, %Context{}, %Opts{})

    expected =
      "Hologram.Interpreter.$less_than_operator({ type: 'integer', value: 1 }, { type: 'integer', value: 2 })"

    assert result == expected
  end
end
