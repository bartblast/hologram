defmodule Hologram.Compiler.JSEncoder.ListSubtractionOperatorTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, JSEncoder, Opts}
  alias Hologram.Compiler.IR.{IntegerType, ListSubtractionOperator, ListType}

  test "encode/3" do
    ir = %ListSubtractionOperator{
      left: %ListType{
        data: [
          %IntegerType{value: 1},
          %IntegerType{value: 2}
        ]
      },
      right: %ListType{
        data: [
          %IntegerType{value: 2},
          %IntegerType{value: 3}
        ]
      }
    }

    result = JSEncoder.encode(ir, %Context{}, %Opts{})

    left =
      "{ type: 'list', data: [ { type: 'integer', value: 1 }, { type: 'integer', value: 2 } ] }"

    right =
      "{ type: 'list', data: [ { type: 'integer', value: 2 }, { type: 'integer', value: 3 } ] }"

    expected = "Elixir_Kernel.$subtract_lists(#{left}, #{right})"

    assert result == expected
  end
end
