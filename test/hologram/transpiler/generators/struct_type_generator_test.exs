defmodule Hologram.Transpiler.StructTypeGeneratorTest do
  use ExUnit.Case, async: true

  alias Hologram.Transpiler.AST.{AtomType, IntegerType, StructType}
  alias Hologram.Transpiler.StructTypeGenerator

  test "generate/1" do
    ast = %StructType{
      data: [{%AtomType{value: :a}, %IntegerType{value: 1}}],
      module: [:Abc, :Bcd]
    }

    context = [module_attributes: []]

    result = StructTypeGenerator.generate(ast.module, ast.data, context)

    expected =
      "{ type: 'struct', module: 'Abc.Bcd', data: { '~Hologram.Transpiler.AST.AtomType[a]': { type: 'integer', value: 1 } } }"

    assert result == expected
  end
end
