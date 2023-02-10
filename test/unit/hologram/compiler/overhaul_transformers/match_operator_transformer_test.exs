defmodule Hologram.Compiler.MatchOperatorTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.MatchOperatorTransformer

  alias Hologram.Compiler.IR.{
    AtomType,
    Binding,
    IntegerType,
    MapAccess,
    MapType,
    MatchAccess,
    MatchOperator,
    Variable
  }

  test "transform/2" do
    code = "%{a: x, b: y} = %{a: 1, b: 2}"
    ast = ast(code)

    result = MatchOperatorTransformer.transform(ast)

    expected = %MatchOperator{
      bindings: [
        %Binding{
          name: :x,
          access_path: [%MatchAccess{}, %MapAccess{key: %AtomType{value: :a}}]
        },
        %Binding{name: :y, access_path: [%MatchAccess{}, %MapAccess{key: %AtomType{value: :b}}]}
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
end
