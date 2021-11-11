defmodule Hologram.Compiler.JSEncoder.MatchOperatorTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, Opts}
  alias Hologram.Compiler.IR.{AtomType, IntegerType, MapAccess, MapType, MatchOperator, Variable}
  alias Hologram.Compiler.JSEncoder

  test "variable" do
    # code:
    # x = 1

    ir = %MatchOperator{
      bindings: [x: []],
      left: %Variable{name: :x},
      right: %IntegerType{value: 1}
    }

    result = JSEncoder.encode(ir, %Context{}, %Opts{})
    expected = "\nconst x = { type: 'integer', value: 1 }\n"

    assert result == expected
  end

  test "map" do
    # code:
    # "%{a: 1, b: %{p: x}, c: 3} = %{a: 1, b: %{p: 9}, c: 3}"

    ir = %MatchOperator{
      bindings: [
        x: [
          %MapAccess{key: %AtomType{value: :b}},
          %MapAccess{key: %AtomType{value: :p}},
        ]
      ],
      left: %MapType{
        data: [
          {%AtomType{value: :a}, %IntegerType{value: 1}},
          {
            %AtomType{value: :b},
            %MapType{
              data: [
                {%AtomType{value: :p}, %Variable{name: :x}}
              ]
            }
          },
          {%AtomType{value: :c}, %IntegerType{value: 3}}
        ]
      },
      right: %MapType{
        data: [
          {%AtomType{value: :a}, %IntegerType{value: 1}},
          {%AtomType{value: :b},
           %MapType{
             data: [
               {%AtomType{value: :p}, %IntegerType{value: 9}},
             ]
           }},
          {%AtomType{value: :c}, %IntegerType{value: 3}}
        ]
      }
    }

    result = JSEncoder.encode(ir, %Context{}, %Opts{})
    expected = "\nconst x = Elixir_Kernel_SpecialForms.$dot(Elixir_Kernel_SpecialForms.$dot({ type: 'map', data: { '~atom[a]': { type: 'integer', value: 1 }, '~atom[b]': { type: 'map', data: { '~atom[p]': { type: 'integer', value: 9 } } }, '~atom[c]': { type: 'integer', value: 3 } } }, { type: 'atom', value: 'b' }), { type: 'atom', value: 'p' })\n"

    assert result == expected
  end

  test "multiple lines" do
    # code:
    # "%{a: x, b: y} = %{a: 1, b: 2}"

    ir = %MatchOperator{
      bindings: [
        x: [
          %MapAccess{key: %AtomType{value: :a}}
        ],
        y: [
          %MapAccess{key: %AtomType{value: :b}}
        ]
      ],
      left: %MapType{
        data: [
          {%AtomType{value: :a}, %Variable{name: :x}},
          {%AtomType{value: :b}, %Variable{name: :y}},
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

    const x = Elixir_Kernel_SpecialForms.$dot({ type: 'map', data: { '~atom[a]': { type: 'integer', value: 1 }, '~atom[b]': { type: 'integer', value: 2 } } }, { type: 'atom', value: 'a' })
    const y = Elixir_Kernel_SpecialForms.$dot({ type: 'map', data: { '~atom[a]': { type: 'integer', value: 1 }, '~atom[b]': { type: 'integer', value: 2 } } }, { type: 'atom', value: 'b' })
    """

    assert result == expected
  end
end
