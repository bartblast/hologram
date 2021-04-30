defmodule Hologram.Transpiler.ListTypeTransformerTest do
  use ExUnit.Case, async: true

  alias Hologram.Transpiler.AST.{IntegerType, ListType}
  alias Hologram.Transpiler.ListTypeTransformer

  setup do
    [
      module: [:Abc],
      imports: [],
      aliases: []
    ]
  end

  test "empty list", context do
    result = ListTypeTransformer.transform([], context)
    expected = %ListType{data: []}

    assert result == expected
  end

  test "non-nested list", context do
    result = ListTypeTransformer.transform([1, 2], context)

    expected = %ListType{
      data: [
        %IntegerType{value: 1},
        %IntegerType{value: 2}
      ]
    }

    assert result == expected
  end

  test "nested list", context do
    result = ListTypeTransformer.transform([1, [2, [3, 4]]], context)

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
