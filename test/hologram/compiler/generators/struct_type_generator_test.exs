defmodule Hologram.Compiler.StructTypeGeneratorTest do
  use ExUnit.Case, async: true

  alias Hologram.Compiler.AST.{AtomType, IntegerType, StructType}
  alias Hologram.Compiler.StructTypeGenerator

  setup do
    []
  end

  test "generate/1", context do
    ast = %StructType{
      data: [{%AtomType{value: :a}, %IntegerType{value: 1}}],
      module: [:Abc, :Bcd]
    }

    result = StructTypeGenerator.generate(ast.module, ast.data, context)

    expected =
      "{ type: 'struct', module: 'Abc.Bcd', data: { '~Hologram.Compiler.AST.AtomType[a]': { type: 'integer', value: 1 } } }"

    assert result == expected
  end
end
