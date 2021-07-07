defmodule Hologram.Compiler.MapTypeGeneratorTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.IR.{AtomType, IntegerType, MapType}
  alias Hologram.Compiler.MapTypeGenerator

  setup do
    [
      context: [],
      opts: []
    ]
  end

  test "generate/3", context do
    ir = %MapType{data: [{%AtomType{value: :a}, %IntegerType{value: 1}}]}

    result = MapTypeGenerator.generate(ir.data, context[:context], context[:opts])

    expected = "{ type: 'map', data: { '~atom[a]': { type: 'integer', value: 1 } } }"

    assert result == expected
  end

  describe "generate_data/3" do
    test "empty data", context do
      data = []

      result = MapTypeGenerator.generate_data(data, context[:context], context[:opts])
      expected = "{}"

      assert result == expected
    end

    test "not nested data", context do
      data = [
        {%AtomType{value: :a}, %IntegerType{value: 1}},
        {%AtomType{value: :b}, %IntegerType{value: 2}}
      ]

      result = MapTypeGenerator.generate_data(data, context[:context], context[:opts])

      expected =
        "{ '~atom[a]': { type: 'integer', value: 1 }, '~atom[b]': { type: 'integer', value: 2 } }"

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

      result = MapTypeGenerator.generate_data(data, context[:context], context[:opts])

      expected =
        "{ '~atom[a]': { type: 'integer', value: 1 }, '~atom[b]': { type: 'map', data: { '~atom[c]': { type: 'integer', value: 2 }, '~atom[d]': { type: 'map', data: { '~atom[e]': { type: 'integer', value: 3 }, '~atom[f]': { type: 'integer', value: 4 } } } } } }"

      assert result == expected
    end
  end
end
