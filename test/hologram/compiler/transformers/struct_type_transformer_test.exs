defmodule Hologram.Compiler.StructTypeTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, StructTypeTransformer}
  alias Hologram.Compiler.IR.{AliasDirective, AtomType, IntegerType, StructType}

  test "not aliased" do
    code = "%Hologram.Test.Fixtures.Compiler.StructTypeTransformer.Module1{a: 1}"
    ast = ast(code)

    result = StructTypeTransformer.transform(ast, %Context{})

    expected = %StructType{
      data: [
        {%AtomType{value: :a}, %IntegerType{value: 1}}
      ],
      module: Hologram.Test.Fixtures.Compiler.StructTypeTransformer.Module1
    }

    assert result == expected
  end

  test "aliased" do
    code = "%Abc{b: 2}"
    ast = ast(code)

    context = %Context{
      aliases: [
        %AliasDirective{module: Hologram.Test.Fixtures.Compiler.StructTypeTransformer.Module2, as: [:Abc]}
      ]
    }

    result = StructTypeTransformer.transform(ast, context)

    expected = %StructType{
      data: [
        {%AtomType{value: :b}, %IntegerType{value: 2}}
      ],
      module: Hologram.Test.Fixtures.Compiler.StructTypeTransformer.Module2
    }

    assert result == expected
  end
end
