defmodule Hologram.Transpiler.Generators.StructTypeGeneratorTest do
  use ExUnit.Case, async: true

  alias Hologram.Transpiler.AST.{AtomType, IntegerType, StructType}
  alias Hologram.Transpiler.Generators.StructTypeGenerator

  test "generate/1"  do
    ast = %StructType{data: [{%AtomType{value: :a}, %IntegerType{value: 1}}], module: [:Abc, :Bcd]}

    result = StructTypeGenerator.generate(ast.module, ast.data)
    expected = "{ type: 'struct', module: 'Abc.Bcd', data: { '~Hologram.Transpiler.AST.AtomType[a]': { type: 'integer', value: 1 } } }"

    assert result == expected
  end
end
