defmodule Hologram.Compiler.StructTypeTransformerTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.AST.{Alias, AtomType, IntegerType, StructType}
  alias Hologram.Compiler.StructTypeTransformer

  test "not aliased" do
    code = "%TestStruct{a: 1}"

    {:%, _, [{_, _, module}, ast]} = ast(code)
    context = [module: [:Abc], imports: [], aliases: []]

    result = StructTypeTransformer.transform(ast, module, context)

    expected =
      %StructType{
        data: [
          {%AtomType{value: :a},
           %IntegerType{value: 1}}
        ],
        module: [:TestStruct]
      }

    assert result == expected
  end

  test "aliased" do
    code = "%Cde{a: 1}"
    {:%, _, [{_, _, module}, ast]} = ast(code)

    context = [
      module: [:Abc],
      imports: [],
      aliases: [
        %Alias{module: [:Bcd, :Cde], as: [:Cde]}
      ]
    ]

    result = StructTypeTransformer.transform(ast, module, context)

    expected =
      %StructType{
        data: [
          {%AtomType{value: :a},
           %IntegerType{value: 1}}
        ],
        module: [:Bcd, :Cde]
      }

    assert result == expected
  end
end
