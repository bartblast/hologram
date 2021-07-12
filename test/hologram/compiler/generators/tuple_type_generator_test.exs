defmodule Hologram.Compiler.TupleTypeGeneratorTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.{Context, TupleTypeGenerator}
  alias Hologram.Compiler.IR.{IntegerType, TupleType}

  @context %Context{module: [], uses: [], imports: [], aliases: [], attributes: []}
  @opts []

  test "empty tuple" do
    result = TupleTypeGenerator.generate([], @context, @opts)
    expected = "{ type: 'tuple', data: [] }"

    assert result == expected
  end

  test "non-empty tuple" do
    data = [%IntegerType{value: 1}, %IntegerType{value: 2}]

    result = TupleTypeGenerator.generate(data, @context, @opts)
    expected = "{ type: 'tuple', data: [ { type: 'integer', value: 1 }, { type: 'integer', value: 2 } ] }"

    assert result == expected
  end
end
