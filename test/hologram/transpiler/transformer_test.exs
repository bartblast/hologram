# TODO: refactor

defmodule Hologram.Transpiler.TransformerTest do
  use ExUnit.Case, async: true

  import Hologram.Transpiler.Parser, only: [parse!: 1]

  alias Hologram.Transpiler.AST.{AtomType, BooleanType, IntegerType, MapType, StringType}
  alias Hologram.Transpiler.AST.MatchOperator
  alias Hologram.Transpiler.AST.MapAccess
  alias Hologram.Transpiler.AST.{Alias, Import, ModuleAttributeOperator, Variable}
  alias Hologram.Transpiler.Transformer
  alias TestModule1
  alias TestModule4

  describe "primitive types" do
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

  describe "operators" do
    test "match operator, simple" do
      result =
        parse!("x = 1")
        |> Transformer.transform()

      expected = %MatchOperator{
        bindings: [[%Variable{name: :x}]],
        left: %Variable{name: :x},
        right: %IntegerType{value: 1}
      }

      assert result == expected
    end

    # TODO: test different kinds of bindings (map, list, etc.)

    test "match operator, map, not nested" do
      result =
        parse!("%{a: x, b: y} = %{a: 1, b: 2}")
        |> Transformer.transform()

      expected = %MatchOperator{
        bindings: [
          [
            %MapAccess{key: %AtomType{value: :a}},
            %Variable{name: :x}
          ],
          [
            %MapAccess{key: %AtomType{value: :b}},
            %Variable{name: :y}
          ]
        ],
        left: %MapType{
          data: [
            {%AtomType{value: :a}, %Variable{name: :x}},
            {%AtomType{value: :b}, %Variable{name: :y}}
          ]
        },
        right: %MapType{
          data: [
            {%AtomType{value: :a}, %IntegerType{value: 1}},
            {%AtomType{value: :b}, %IntegerType{value: 2}}
          ]
        }
      }

      assert result == expected
    end

    test "match operator, map, nested" do
      code =
        "%{a: 1, b: %{p: x, r: 4}, c: 3, d: %{m: 0, n: y}} = %{a: 1, b: %{p: 9, r: 4}, c: 3, d: %{m: 0, n: 8}}"

      result =
        parse!(code)
        |> Transformer.transform()

      expected = %MatchOperator{
        bindings: [
          [
            %MapAccess{key: %AtomType{value: :b}},
            %MapAccess{key: %AtomType{value: :p}},
            %Variable{name: :x}
          ],
          [
            %MapAccess{key: %AtomType{value: :d}},
            %MapAccess{key: %AtomType{value: :n}},
            %Variable{name: :y}
          ]
        ],
        left: %MapType{
          data: [
            {%AtomType{value: :a}, %IntegerType{value: 1}},
            {
              %AtomType{value: :b},
              %MapType{
                data: [
                  {%AtomType{value: :p}, %Variable{name: :x}},
                  {%AtomType{value: :r}, %IntegerType{value: 4}}
                ]
              }
            },
            {%AtomType{value: :c}, %IntegerType{value: 3}},
            {%AtomType{value: :d},
             %MapType{
               data: [
                 {%AtomType{value: :m}, %IntegerType{value: 0}},
                 {%AtomType{value: :n}, %Variable{name: :y}}
               ]
             }}
          ]
        },
        right: %MapType{
          data: [
            {%AtomType{value: :a}, %IntegerType{value: 1}},
            {%AtomType{value: :b},
             %MapType{
               data: [
                 {%AtomType{value: :p}, %IntegerType{value: 9}},
                 {%AtomType{value: :r}, %IntegerType{value: 4}}
               ]
             }},
            {%AtomType{value: :c}, %IntegerType{value: 3}},
            {%AtomType{value: :d},
             %MapType{
               data: [
                 {%AtomType{value: :m}, %IntegerType{value: 0}},
                 {%AtomType{value: :n}, %IntegerType{value: 8}}
               ]
             }}
          ]
        }
      }

      assert result == expected
    end
  end

  describe "other" do
    test "import" do
      result =
        parse!("import Prefix.Test")
        |> Transformer.transform()

      expected = %Import{module: [:Prefix, :Test]}

      assert result == expected
    end

    test "alias" do
      result =
        parse!("alias Prefix.Test")
        |> Transformer.transform()

      expected = %Alias{module: [:Prefix, :Test], as: [:Test]}

      assert result == expected
    end

    test "variable" do
      ast = parse!("x")
      assert Transformer.transform(ast) == %Variable{name: :x}
    end

    test "module attribute" do
      ast = parse!("@x")
      assert Transformer.transform(ast) == %ModuleAttributeOperator{name: :x}
    end
  end
end
