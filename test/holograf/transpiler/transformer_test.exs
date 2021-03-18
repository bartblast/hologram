defmodule Holograf.Transpiler.TransformerTest do
  use ExUnit.Case

  import Holograf.Transpiler.Parser, only: [parse!: 1]

  alias Holograf.Transpiler.AST.{AtomType, BooleanType, IntegerType, StringType}
  alias Holograf.Transpiler.AST.MapType
  alias Holograf.Transpiler.Transformer

  describe "primitives" do
    test "atom" do
      ast = parse!(":test")
      assert Transformer.transform(ast) == %AtomType{value: :test}
    end

    test "boolean" do
      ast = parse!("true")
      assert Transformer.transform(ast) == %BooleanType{value: true}
    end

    test "integer" do
      ast = parse!("1")
      assert Transformer.transform(ast) == %IntegerType{value: 1}
    end

    test "string" do
      ast = parse!("\"test\"")
      assert Transformer.transform(ast) == %StringType{value: "test"}
    end
  end

  describe "data structures" do
    test "map, empty" do
      result =
        parse!("%{}")
        |> Transformer.transform()

      expected = %MapType{data: []}

      assert result == expected
    end

    test "map, not nested" do
      result =
        parse!("%{a: 1, b: 2}")
        |> Transformer.transform()

      expected = %MapType{
        data: [
          {%AtomType{value: :a}, %IntegerType{value: 1}},
          {%AtomType{value: :b}, %IntegerType{value: 2}}
        ]
      }

      assert result == expected
    end

    test "map, nested" do
      result =
        parse!("%{a: 1, b: %{c: 2, d: %{e: 3, f: 4}}}")
        |> Transformer.transform()

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
end
