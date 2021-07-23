defmodule Hologram.Compiler.ListTypeGeneratorTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.{Context, ListTypeGenerator}
  alias Hologram.Compiler.IR.{IntegerType, ListType}

  @context %Context{module: nil, uses: [], imports: [], aliases: [], attributes: []}
  @opts []

  test "empty list" do
    result = ListTypeGenerator.generate([], @context, @opts)
    expected = "{ type: 'list', data: [] }"

    assert result == expected
  end

  test "non-empty list" do
    data = [%IntegerType{value: 1}, %IntegerType{value: 2}]

    result = ListTypeGenerator.generate(data, @context, @opts)
    expected = "{ type: 'list', data: [ { type: 'integer', value: 1 }, { type: 'integer', value: 2 } ] }"

    assert result == expected
  end

  test "nested list" do
    data = [
      %IntegerType{value: 1},
      %ListType{
        data: [
          %IntegerType{value: 2},
          %IntegerType{value: 3}
        ]
      }
    ]

    result = ListTypeGenerator.generate(data, @context, @opts)
    expected = "{ type: 'list', data: [ { type: 'integer', value: 1 }, { type: 'list', data: [ { type: 'integer', value: 2 }, { type: 'integer', value: 3 } ] } ] }"

    assert result == expected
  end
end
