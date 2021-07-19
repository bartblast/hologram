defmodule Hologram.Compiler.StructTypeTransformerTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.IR.{Alias, AtomType, IntegerType, StructType}
  alias Hologram.Compiler.{Context, StructTypeTransformer}

  test "not aliased" do
    code = "%Hologram.Test.Fixtures.Compiler.StructTypeTransformer.Module1{a: 1}"

    {:%, _, [{_, _, module_segs}, ast]} = ast(code)
    context = %Context{module: nil, uses: [], imports: [], aliases: [], attributes: []}

    result = StructTypeTransformer.transform(ast, module_segs, context)

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
    {:%, _, [{_, _, module_segs}, ast]} = ast(code)

    context = %Context{
      module: nil,
      uses: [],
      imports: [],
      aliases: [
        %Alias{module: Hologram.Test.Fixtures.Compiler.StructTypeTransformer.Module2, as: [:Abc]}
      ],
      attributes: []
    }

    result = StructTypeTransformer.transform(ast, module_segs, context)

    expected = %StructType{
      data: [
        {%AtomType{value: :b}, %IntegerType{value: 2}}
      ],
      module: Hologram.Test.Fixtures.Compiler.StructTypeTransformer.Module2
    }

    assert result == expected
  end
end
