defmodule Hologram.Compiler.TupleTypeGeneratorTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.{Context, TupleTypeGenerator}
  alias Hologram.Compiler.IR.IntegerType

  @context %Context{module: nil, uses: [], imports: [], aliases: [], attributes: []}
  @opts []

  test "generate/3" do
    data = [%IntegerType{value: 1}, %IntegerType{value: 2}]

    result = TupleTypeGenerator.generate(data, @context, @opts)
    expected = "{ type: 'tuple', data: [ { type: 'integer', value: 1 }, { type: 'integer', value: 2 } ] }"

    assert result == expected
  end
end
