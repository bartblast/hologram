defmodule Hologram.Compiler.ListTypeTransformerTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.{Context, ListTypeTransformer}
  alias Hologram.Compiler.IR.{IntegerType, ListType}

  @context %Context{
    module: [:Abc],
    uses: [],
    imports: [],
    aliases: [],
    attributes: []
  }

  test "empty list" do
    code = "[]"
    ast = ast(code)

    result = ListTypeTransformer.transform(ast, @context)
    expected = %ListType{data: []}

    assert result == expected
  end

  test "non-nested list" do
    code = "[1, 2]"
    ast = ast(code)

    result = ListTypeTransformer.transform(ast, @context)

    expected = %ListType{
      data: [
        %IntegerType{value: 1},
        %IntegerType{value: 2}
      ]
    }

    assert result == expected
  end

  test "nested list" do
    code = "[1, [2, [3, 4]]]"
    ast = ast(code)

    result = ListTypeTransformer.transform(ast, @context)

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
