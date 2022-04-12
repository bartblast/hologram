defmodule Hologram.Compiler.JSEncoder.ConsOperatorTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, JSEncoder, Opts}
  alias Hologram.Compiler.IR.{ConsOperator, IntegerType, ListType}

  test "encode/3" do
    ir = %ConsOperator{
      head: %IntegerType{value: 1},
      tail: %ListType{
        data: [
          %IntegerType{value: 2},
          %IntegerType{value: 3}
        ]
      }
    }

    result = JSEncoder.encode(ir, %Context{}, %Opts{})

    head = "{ type: 'integer', value: 1 }"

    tail =
      "{ type: 'list', data: [ { type: 'integer', value: 2 }, { type: 'integer', value: 3 } ] }"

    expected = "Hologram.Interpreter.$cons_operator(#{head}, #{tail})"

    assert result == expected
  end
end
