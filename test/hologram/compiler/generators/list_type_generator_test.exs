defmodule Hologram.Compiler.ListTypeGeneratorTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.{Context, ListTypeGenerator}
  alias Hologram.Compiler.IR.IntegerType

  @context %Context{module: nil, uses: [], imports: [], aliases: [], attributes: []}
  @opts []

  test "generate/3" do
    data = [%IntegerType{value: 1}, %IntegerType{value: 2}]

    result = ListTypeGenerator.generate(data, @context, @opts)
    expected = "{ type: 'list', data: [ { type: 'integer', value: 1 }, { type: 'integer', value: 2 } ] }"

    assert result == expected
  end
end
