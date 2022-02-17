defmodule Hologram.Compiler.JSEncoder.ListConcatenationOperatorTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, JSEncoder, Opts}
  alias Hologram.Compiler.IR.{IntegerType, ListConcatenationOperator, ListType}

  test "encode/3" do
    ir = %ListConcatenationOperator{
      left: %ListType{
        data: [
          %IntegerType{value: 1},
          %IntegerType{value: 2}
        ]
      },
      right:  %ListType{
        data: [
          %IntegerType{value: 3},
          %IntegerType{value: 4}
        ]
      }
    }

    result = JSEncoder.encode(ir, %Context{}, %Opts{})

    left = "{ type: 'list', data: [ { type: 'integer', value: 1 }, { type: 'integer', value: 2 } ] }"
    right = "{ type: 'list', data: [ { type: 'integer', value: 3 }, { type: 'integer', value: 4 } ] }"
    expected = "Elixir_Kernel.$concatenate_lists(#{left}, #{right})"

    assert result == expected
  end
end
