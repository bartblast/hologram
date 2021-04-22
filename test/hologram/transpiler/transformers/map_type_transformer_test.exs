defmodule Hologram.Transpiler.MapTypeTransformerTest do
  use ExUnit.Case, async: true

  alias Hologram.Transpiler.AST.{AtomType, IntegerType, MapType}
  alias Hologram.Transpiler.MapTypeTransformer

  test "empty map" do
    result = MapTypeTransformer.transform([], [:Abc], [], [])
    expected = %MapType{data: []}

    assert result == expected
  end

  test "non-nested map" do
    result = MapTypeTransformer.transform([a: 1, b: 2], [:Abc], [], [])

    expected = %MapType{
      data: [
        {%AtomType{value: :a}, %IntegerType{value: 1}},
        {%AtomType{value: :b}, %IntegerType{value: 2}}
      ]
    }

    assert result == expected
  end

  test "nested map" do
    ast = [
      a: 1,
      b: {:%{}, [line: 1], [
        c: 2,
        d: {:%{}, [line: 1], [
          e: 3,
          f: 4
        ]}
      ]}
    ]

    result = MapTypeTransformer.transform(ast, [:Abc], [], [])

    expected = %MapType{
      data: [
        {%AtomType{value: :a}, %IntegerType{value: 1}},
        {%AtomType{value: :b},
         %MapType{
           data: [
             {%AtomType{value: :c}, %IntegerType{value: 2}},
             {%AtomType{value: :d},
              %MapType{
                data: [
                  {%AtomType{value: :e}, %IntegerType{value: 3}},
                  {%AtomType{value: :f}, %IntegerType{value: 4}}
                ]
              }}
           ]
         }}
      ]
    }

    assert result == expected
  end
end
