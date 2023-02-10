defmodule Hologram.Compiler.MembershipOperatorTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR.{IntegerType, ListType, MembershipOperator}
  alias Hologram.Compiler.MembershipOperatorTransformer

  test "transform/3" do
    code = "1 in [1, 2]"
    ast = ast(code)

    result = MembershipOperatorTransformer.transform(ast)

    expected = %MembershipOperator{
      left: %IntegerType{value: 1},
      right: %ListType{
        data: [
          %IntegerType{value: 1},
          %IntegerType{value: 2}
        ]
      }
    }

    assert result == expected
  end
end
