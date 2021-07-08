defmodule Hologram.Compiler.StructTypeGeneratorTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.{Context, StructTypeGenerator}
  alias Hologram.Compiler.IR.{AtomType, IntegerType}

  test "generate/4" do
    data = [{%AtomType{value: :a}, %IntegerType{value: 1}}]
    module = [:Abc, :Bcd]
    context = %Context{module: [], uses: [], imports: [], aliases: [], attributes: []}

    result = StructTypeGenerator.generate(module, data, context, [])

    expected =
      "{ type: 'struct', module: 'Abc.Bcd', data: { '~atom[a]': { type: 'integer', value: 1 } } }"

    assert result == expected
  end
end
