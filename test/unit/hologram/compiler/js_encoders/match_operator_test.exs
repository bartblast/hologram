defmodule Hologram.Compiler.JSEncoder.MatchOperatorTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Config, Context, Opts}

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

  alias Hologram.Compiler.JSEncoder

  @rhsExprVar Config.rightHandSideExpressionVar()

  test "encode/3" do
    # code:
    # %{a: x, b: y} = %{a: 1, b: 2}

    ir = %MatchOperator{
      bindings: [
        %Binding{
          name: :x,
          access_path: [
            %VariableAccess{name: @rhsExprVar},
            %MapAccess{key: %AtomType{value: :a}}
          ]
        },
        %Binding{
          name: :y,
          access_path: [
            %VariableAccess{name: @rhsExprVar},
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
    #{@rhsExprVar} = { type: 'map', data: { '~atom[a]': { type: 'integer', value: 1 }, '~atom[b]': { type: 'integer', value: 2 } } };
    let x = #{@rhsExprVar}.data['~atom[a]'];
    let y = #{@rhsExprVar}.data['~atom[b]'];\
    """

    assert result == expected
  end
end
