defmodule Hologram.Compiler.StructTypeTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.Context
  alias Hologram.Compiler.IR.AtomType
  alias Hologram.Compiler.IR.IntegerType
  alias Hologram.Compiler.IR.StructType
  alias Hologram.Compiler.StructTypeTransformer

  test "transform/3" do
    code = "%Abc.Bcd{x: 1, y: 2}"
    ast = ast(code)

    result = StructTypeTransformer.transform(ast, %Context{})

    expected = %StructType{
      alias_segs: [:Abc, :Bcd],
      data: [
        {%AtomType{value: :x}, %IntegerType{value: 1}},
        {%AtomType{value: :y}, %IntegerType{value: 2}}
      ],
      module: nil
    }

    assert result == expected
  end
end
