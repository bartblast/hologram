defmodule Hologram.Compiler.StructTypeGeneratorTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.{Context, StructTypeGenerator}
  alias Hologram.Compiler.IR.{AtomType, IntegerType}

  test "generate/4" do
    data = [{%AtomType{value: :a}, %IntegerType{value: 1}}]
    context = %Context{module: nil, uses: [], imports: [], aliases: [], attributes: []}

    result = StructTypeGenerator.generate(Abc.Bcd, data, context, [])

    expected =
      "{ type: 'struct', module: 'Elixir_Abc_Bcd', data: { '~atom[a]': { type: 'integer', value: 1 } } }"

    assert result == expected
  end
end
