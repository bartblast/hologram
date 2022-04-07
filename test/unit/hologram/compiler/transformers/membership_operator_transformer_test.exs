defmodule Hologram.Compiler.MembershipOperatorTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, MembershipOperatorTransformer}
  alias Hologram.Compiler.IR.{IntegerType, ListType, MembershipOperator}

  test "transform/3" do
    code = "1 in [1, 2]"
    ast = ast(code)

    result = MembershipOperatorTransformer.transform(ast, %Context{})

    expected = %MembershipOperator{
      left: %IntegerType{value: 1},
      right: %ListType{data: [
        %IntegerType{value: 1},
        %IntegerType{value: 2}
      ]}
    }

    assert result == expected
  end
end
