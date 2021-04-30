defmodule Hologram.Transpiler.MapTypeGeneratorTest do
  use ExUnit.Case, async: true

  alias Hologram.Transpiler.AST.{AtomType, IntegerType, MapType}
  alias Hologram.Transpiler.MapTypeGenerator

  setup do
    [
      module_attributes: []
    ]
  end

  test "generate/1", context do
    ast = %MapType{data: [{%AtomType{value: :a}, %IntegerType{value: 1}}]}

    result = MapTypeGenerator.generate(ast.data, context)

    expected =
      "{ type: 'map', data: { '~Hologram.Transpiler.AST.AtomType[a]': { type: 'integer', value: 1 } } }"

    assert result == expected
  end

  describe "generate_data/1" do
    test "empty data", context do
      data = []

      result = MapTypeGenerator.generate_data(data, context)
      expected = "{}"

      assert result == expected
    end

    test "not nested data", context do
      data = [
        {%AtomType{value: :a}, %IntegerType{value: 1}},
        {%AtomType{value: :b}, %IntegerType{value: 2}}
      ]

      result = MapTypeGenerator.generate_data(data, context)

      expected =
        "{ '~Hologram.Transpiler.AST.AtomType[a]': { type: 'integer', value: 1 }, '~Hologram.Transpiler.AST.AtomType[b]': { type: 'integer', value: 2 } }"

      assert result == expected
    end

    test "nested data", context do
      data = [
        {%AtomType{value: :a}, %IntegerType{value: 1}},
        {
          %AtomType{value: :b},
          %MapType{
            data: [
              {%AtomType{value: :c}, %IntegerType{value: 2}},
              {
                %AtomType{value: :d},
                %MapType{
                  data: [
                    {%AtomType{value: :e}, %IntegerType{value: 3}},
                    {%AtomType{value: :f}, %IntegerType{value: 4}}
                  ]
                }
              }
            ]
          }
        }
      ]

      result = MapTypeGenerator.generate_data(data, context)

      expected =
        "{ '~Hologram.Transpiler.AST.AtomType[a]': { type: 'integer', value: 1 }, '~Hologram.Transpiler.AST.AtomType[b]': { type: 'map', data: { '~Hologram.Transpiler.AST.AtomType[c]': { type: 'integer', value: 2 }, '~Hologram.Transpiler.AST.AtomType[d]': { type: 'map', data: { '~Hologram.Transpiler.AST.AtomType[e]': { type: 'integer', value: 3 }, '~Hologram.Transpiler.AST.AtomType[f]': { type: 'integer', value: 4 } } } } } }"

      assert result == expected
    end
  end
end
