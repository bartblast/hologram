defmodule Hologram.Compiler.ListTypeTransformerTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.IR.{IntegerType, ListType}
  alias Hologram.Compiler.ListTypeTransformer

  setup do
    [
      module: [:Abc],
      imports: [],
      aliases: []
    ]
  end

  test "empty list", context do
    code = "[]"
    ast = ast(code)

    result = ListTypeTransformer.transform(ast, context)
    expected = %ListType{data: []}

    assert result == expected
  end

  test "non-nested list", context do
    code = "[1, 2]"
    ast = ast(code)

    result = ListTypeTransformer.transform(ast, context)

    expected = %ListType{
      data: [
        %IntegerType{value: 1},
        %IntegerType{value: 2}
      ]
    }

    assert result == expected
  end

  test "nested list", context do
    code = "[1, [2, [3, 4]]]"
    ast = ast(code)

    result = ListTypeTransformer.transform(ast, context)

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
