defmodule Hologram.Transpiler.StructTypeTransformerTest do
  use ExUnit.Case, async: true
  import Hologram.Transpiler.Parser, only: [parse!: 1]

  alias Hologram.Transpiler.AST.{Alias, AtomType, IntegerType, StructType}
  alias Hologram.Transpiler.StructTypeTransformer

   test "not aliased" do
    ast = {:%{}, [line: 1], [a: 2]}

    result = StructTypeTransformer.transform(ast, [:Abc], [:Bcd], [], [])

    expected = %StructType{
      data: [
        {
          %AtomType{value: :a},
          %IntegerType{value: 2}
        }
      ],
      module: [:Abc]
    }

    assert result == expected
  end

  test "aliased" do
    ast = {:%{}, [line: 1], [a: 2]}

    aliases = [
      %Alias{module: [:Abc, :Bcd], as: [:Bcd]},
      %Alias{module: [:Bcd, :Cde], as: [:Cde]}
    ]

    result = StructTypeTransformer.transform(ast, [:Cde], [:Xyz], [], aliases)

    expected = %StructType{
      data: [
        {
          %AtomType{value: :a},
          %IntegerType{value: 2}
        }
      ],
      module: [:Bcd, :Cde]
    }

    assert result == expected
  end
end
