defmodule Hologram.Compiler.TupleTypeTransformerTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.{Context, TupleTypeTransformer}
  alias Hologram.Compiler.IR.{IntegerType, TupleType}

  @context %Context{
    module: [:Abc],
    uses: [],
    imports: [],
    aliases: [],
    attributes: []
  }

  test "empty tuple" do
    code = "{}"
    {:{}, _, list} = ast(code)

    result = TupleTypeTransformer.transform(list, @context)
    expected = %TupleType{data: []}

    assert result == expected
  end

  test "1 element tuple" do
    code = "{}"
    {:{}, _, list} = ast(code)

    result = TupleTypeTransformer.transform(list, @context)
    expected = %TupleType{data: []}

    assert result == expected
  end

  test "2 element tuple" do
    code = "{1, 2}"
    ast = ast(code)

    result = TupleTypeTransformer.transform(ast, @context)

    expected =
      %TupleType{
        data: [
          %IntegerType{value: 1},
          %IntegerType{value: 2}
        ]
      }

    assert result == expected
  end

  test "3 element tuple" do
    code = "{1, 2, 3}"
    {:{}, _, list} = ast(code)

    result = TupleTypeTransformer.transform(list, @context)

    expected =
      %TupleType{
        data: [
          %IntegerType{value: 1},
          %IntegerType{value: 2},
          %IntegerType{value: 3}
        ]
      }

    assert result == expected
  end

  test "nested tuple" do
    code = "{1, {2, {3, 4, 5}, 6}, 7}"
    {:{}, _, list} = ast(code)

    result = TupleTypeTransformer.transform(list, @context)

    expected =
      %TupleType{
        data: [
          %IntegerType{value: 1},
          %TupleType{
            data: [
              %IntegerType{value: 2},
              %TupleType{
                data: [
                  %IntegerType{value: 3},
                  %IntegerType{value: 4},
                  %IntegerType{value: 5}
                ]
              },
              %IntegerType{value: 6}
            ]
          },
          %IntegerType{value: 7}
        ]
      }

    assert result == expected
  end
end
