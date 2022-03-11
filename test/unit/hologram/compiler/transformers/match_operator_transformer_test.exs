defmodule Hologram.Compiler.MatchOperatorTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, MatchOperatorTransformer}

  alias Hologram.Compiler.IR.{
    AtomType,
    Binding,
    IntegerType,
    MapAccess,
    MapType,
    MatchOperator,
    Variable,
    VariableAccess
  }

  test "variable" do
    code = "x = 1"
    ast = ast(code)

    result = MatchOperatorTransformer.transform(ast, %Context{})

    expected = %MatchOperator{
      bindings: [%Binding{name: :x, access_path: [%VariableAccess{name: "window.$rightHandSide"}]}],
      left: %Variable{name: :x},
      right: %IntegerType{value: 1}
    }

    assert result == expected
  end

  describe "map" do
    test "not nested" do
      code = "%{a: x, b: y} = %{a: 1, b: 2}"
      ast = ast(code)

      result = MatchOperatorTransformer.transform(ast, %Context{})

      expected = %MatchOperator{
        bindings: [
          %Binding{name: :x, access_path: [%VariableAccess{name: "window.$rightHandSide"}, %MapAccess{key: %AtomType{value: :a}}]},
          %Binding{name: :y, access_path: [%VariableAccess{name: "window.$rightHandSide"}, %MapAccess{key: %AtomType{value: :b}}]},
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

    test "nested" do
      code =
        "%{a: 1, b: %{p: x, r: 4}, c: 3, d: %{m: 0, n: y}} = %{a: 1, b: %{p: 9, r: 4}, c: 3, d: %{m: 0, n: 8}}"

      ast = ast(code)

      result = MatchOperatorTransformer.transform(ast, %Context{})

      expected = %MatchOperator{
        bindings: [
          %Binding{name: :x, access_path: [
            %VariableAccess{name: "window.$rightHandSide"},
            %MapAccess{key: %AtomType{value: :b}},
            %MapAccess{key: %AtomType{value: :p}}
          ]},
          %Binding{name: :y, access_path: [
            %VariableAccess{name: "window.$rightHandSide"},
            %MapAccess{key: %AtomType{value: :d}},
            %MapAccess{key: %AtomType{value: :n}}
          ]}
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
  # TODO: test other types
end
