defmodule Hologram.Compiler.JSEncoder.MembershipOperatorTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, JSEncoder, Opts}
  alias Hologram.Compiler.IR.{IntegerType, ListType, MembershipOperator}

  test "encode/3" do
    ir = %MembershipOperator{
      left: %IntegerType{value: 1},
      right: %ListType{
        data: [
          %IntegerType{value: 1},
          %IntegerType{value: 2}
        ]
      }
    }

    result = JSEncoder.encode(ir, %Context{}, %Opts{})

    integer_1 = "{ type: 'integer', value: 1 }"
    integer_2 = "{ type: 'integer', value: 2 }"
    list = "{ type: 'list', data: [ #{integer_1}, #{integer_2} ] }"

    expected = "Hologram.Interpreter.$membership_operator(#{integer_1}, #{list})"

    assert result == expected
  end
end
