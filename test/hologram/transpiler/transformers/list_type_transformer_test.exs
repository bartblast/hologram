defmodule Hologram.Transpiler.ListTypeTransformerTest do
  use ExUnit.Case, async: true

  alias Hologram.Transpiler.AST.{IntegerType, ListType}
  alias Hologram.Transpiler.ListTypeTransformer

  test "empty list" do
    result = ListTypeTransformer.transform([], [:Abc], [], [])
    expected = %ListType{data: []}

    assert result == expected
  end

  test "non-nested list" do
    result = ListTypeTransformer.transform([1, 2], [:Abc], [], [])

    expected = %ListType{
      data: [
        %IntegerType{value: 1},
        %IntegerType{value: 2}
      ]
    }

    assert result == expected
  end

  test "nested list" do
    result = ListTypeTransformer.transform([1, [2, [3, 4]]], [:Abc], [], [])

    expected = %ListType{
      data: [
        %IntegerType{value: 1},
        %ListType{
          data: [
            %IntegerType{value: 2},
            %ListType{
              data: [
                %IntegerType{value: 3},
                %IntegerType{value: 4}
              ]
            }
          ]
        }
      ]
    }

    assert result == expected
  end
end
