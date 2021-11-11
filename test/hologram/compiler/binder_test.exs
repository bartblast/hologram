defmodule Hologram.Compiler.BinderTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.Binder
  alias Hologram.Compiler.IR.{AtomType, IntegerType, MapAccess, MapType, Variable}

  describe "map" do
    test "non-nested map without vars" do
      ir = %MapType{
        data: [
          {%AtomType{value: :a}, %IntegerType{value: 1}},
          {%AtomType{value: :b}, %IntegerType{value: 2}}
        ]
      }

      assert Binder.bind(ir) == []
    end

    test "non-nested map with single var" do
      ir = %MapType{
        data: [
          {%AtomType{value: :a}, %IntegerType{value: 1}},
          {%AtomType{value: :b}, %Variable{name: :x}}
        ]
      }

      result = Binder.bind(ir)

      expected = [
        [
          %MapAccess{
            key: %AtomType{value: :b}
          },
          %Variable{name: :x}
        ]
      ]

      assert result == expected
    end

    test "non-nested map with multiple vars" do
      ir = %MapType{
        data: [
          {%AtomType{value: :a}, %Variable{name: :x}},
          {%AtomType{value: :b}, %IntegerType{value: 2}},
          {%AtomType{value: :c}, %Variable{name: :y}}
        ]
      }

      result = Binder.bind(ir)

      expected = [
        [
          %MapAccess{
            key: %AtomType{value: :a}
          },
          %Variable{name: :x}
        ],
        [
          %MapAccess{
            key: %AtomType{value: :c}
          },
          %Variable{name: :y}
        ]
      ]

      assert result == expected
    end

    test "nested map without vars" do
      ir = %MapType{
        data: [
          {%AtomType{value: :a}, %IntegerType{value: 1}},
          {%AtomType{value: :b},
           %MapType{
             data: [
               {%AtomType{value: :c}, %IntegerType{value: 3}},
               {%AtomType{value: :d}, %IntegerType{value: 4}}
             ]
           }}
        ]
      }

      assert Binder.bind(ir) == []
    end

    test "nested map with single var" do
      ir = %MapType{
        data: [
          {%AtomType{value: :a}, %IntegerType{value: 1}},
          {%AtomType{value: :b},
           %MapType{
             data: [
               {%AtomType{value: :c}, %Variable{name: :x}},
               {%AtomType{value: :d}, %IntegerType{value: 4}}
             ]
           }}
        ]
      }

      result = Binder.bind(ir)

      expected = [
        [
          %MapAccess{
            key: %AtomType{value: :b}
          },
          %MapAccess{
            key: %AtomType{value: :c}
          },
          %Variable{name: :x}
        ]
      ]

      assert result == expected
    end

    test "nested map with multiple vars" do
      ir = %MapType{
        data: [
          {%AtomType{value: :a}, %IntegerType{value: 1}},
          {%AtomType{value: :b}, %Variable{name: :x}},
          {%AtomType{value: :c},
           %MapType{
             data: [
               {%AtomType{value: :d}, %Variable{name: :y}},
               {%AtomType{value: :e}, %IntegerType{value: 4}}
             ]
           }}
        ]
      }

      result = Binder.bind(ir)

      expected = [
        [
          %MapAccess{
            key: %AtomType{value: :b}
          },
          %Variable{name: :x}
        ],
        [
          %MapAccess{
            key: %AtomType{value: :c}
          },
          %MapAccess{
            key: %AtomType{value: :d}
          },
          %Variable{name: :y}
        ]
      ]

      assert result == expected
    end
  end

  test "variable" do
    ir = %Variable{name: :test}
    expected = [[%Variable{name: :test}]]
    assert Binder.bind(ir) == expected
  end
end
