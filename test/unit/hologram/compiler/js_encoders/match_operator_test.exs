defmodule Hologram.Compiler.JSEncoder.MatchOperatorTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, Opts}

  alias Hologram.Compiler.IR.{
    AtomType,
    Binding,
    IntegerType,
    MapAccess,
    MapType,
    MatchOperator,
    TupleType,
    Variable
  }

  alias Hologram.Compiler.JSEncoder

  test "encode/3" do
    # code:
    # "%{a: x, b: y} = %{a: 1, b: 2}"

    ir = %MatchOperator{
      bindings: [
        %Binding{
          name: :x,
          access_path: [
            %MapAccess{key: %AtomType{value: :a}}
          ]
        },
        %Binding{
          name: :y,
          access_path: [
            %MapAccess{key: %AtomType{value: :b}}
          ]
        }
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

    result = JSEncoder.encode(ir, %Context{}, %Opts{})

    expected = """
    window.hologramExpressionRightHandSide = { type: 'map', data: { '~atom[a]': { type: 'integer', value: 1 }, '~atom[b]': { type: 'integer', value: 2 } } };
    let x = window.hologramExpressionRightHandSide.data['~atom[a]'];
    let y = window.hologramExpressionRightHandSide.data['~atom[b]'];\
    """

    assert result == expected
  end
end
