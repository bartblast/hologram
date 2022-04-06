defmodule Hologram.Compiler.BindingsTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.Bindings

  alias Hologram.Compiler.IR.{
    AtomType,
    IntegerType,
    MapAccess,
    MapType,
    TupleAccess,
    TupleType,
    Variable
  }

  describe "map" do
    test "non-nested map without vars" do
      ir = %MapType{
        data: [
          {%AtomType{value: :a}, %IntegerType{value: 1}},
          {%AtomType{value: :b}, %IntegerType{value: 2}}
        ]
      }

      assert Bindings.find(ir) == []
    end

    test "non-nested map with single var" do
      ir = %MapType{
        data: [
          {%AtomType{value: :a}, %IntegerType{value: 1}},
          {%AtomType{value: :b}, %Variable{name: :x}}
        ]
      }

      result = Bindings.find(ir)

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

      result = Bindings.find(ir)

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

      assert Bindings.find(ir) == []
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

      result = Bindings.find(ir)

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

      result = Bindings.find(ir)

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

  describe "tuple" do
    test "non-nested tuple without vars" do
      ir = %TupleType{
        data: [
          %IntegerType{value: 1},
          %IntegerType{value: 2}
        ]
      }

      assert Bindings.find(ir) == []
    end

    test "non-nested tuple with single var" do
      ir = %TupleType{
        data: [
          %IntegerType{value: 1},
          %Variable{name: :x}
        ]
      }

      result = Bindings.find(ir)

      expected = [
        [
          %TupleAccess{index: 1},
          %Variable{name: :x}
        ]
      ]

      assert result == expected
    end

    test "non-nested tuple with multiple vars" do
      ir = %TupleType{
        data: [
          %Variable{name: :x},
          %IntegerType{value: 2},
          %Variable{name: :y}
        ]
      }

      result = Bindings.find(ir)

      expected = [
        [
          %TupleAccess{index: 0},
          %Variable{name: :x}
        ],
        [
          %TupleAccess{index: 2},
          %Variable{name: :y}
        ]
      ]

      assert result == expected
    end

    test "nested tuple without vars" do
      ir = %TupleType{
        data: [
          %IntegerType{value: 1},
          %IntegerType{value: 2},
          %TupleType{
            data: [
              %IntegerType{value: 3},
              %IntegerType{value: 4}
            ]
          }
        ]
      }

      assert Bindings.find(ir) == []
    end

    test "nested tuple with single var" do
      ir = %TupleType{
        data: [
          %IntegerType{value: 1},
          %TupleType{
            data: [
              %Variable{name: :x},
              %IntegerType{value: 2}
            ]
          }
        ]
      }

      result = Bindings.find(ir)

      expected = [
        [
          %TupleAccess{index: 1},
          %TupleAccess{index: 0},
          %Variable{name: :x}
        ]
      ]

      assert result == expected
    end

    test "nested tuple with multiple vars" do
      ir = %TupleType{
        data: [
          %IntegerType{value: 1},
          %Variable{name: :x},
          %TupleType{
            data: [
              %Variable{name: :y},
              %IntegerType{value: 2}
            ]
          }
        ]
      }

      result = Bindings.find(ir)

      expected = [
        [
          %TupleAccess{index: 1},
          %Variable{name: :x}
        ],
        [
          %TupleAccess{index: 2},
          %TupleAccess{index: 0},
          %Variable{name: :y}
        ]
      ]

      assert result == expected
    end
  end

  test "variable" do
    ir = %Variable{name: :test}
    expected = [[%Variable{name: :test}]]
    assert Bindings.find(ir) == expected
  end
end
