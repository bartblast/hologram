defmodule Hologram.Compiler.PatternDeconstructor.TupleTypeTest do
  use Hologram.Test.UnitCase, async: false

  alias Hologram.Compiler.IR.IntegerType
  alias Hologram.Compiler.IR.Symbol
  alias Hologram.Compiler.IR.TupleAccess
  alias Hologram.Compiler.IR.TupleType
  alias Hologram.Compiler.PatternDeconstructor

  test "non-nested tuple without vars" do
    ir = %TupleType{
      data: [
        %IntegerType{value: 1},
        %IntegerType{value: 2}
      ]
    }

    assert PatternDeconstructor.deconstruct(ir) == []
  end

  test "non-nested tuple with single var" do
    ir = %TupleType{
      data: [
        %IntegerType{value: 1},
        %Symbol{name: :x}
      ]
    }

    result = PatternDeconstructor.deconstruct(ir)

    expected = [
      [
        %TupleAccess{index: 1},
        %Symbol{name: :x}
      ]
    ]

    assert result == expected
  end

  test "non-nested tuple with multiple vars" do
    ir = %TupleType{
      data: [
        %Symbol{name: :x},
        %IntegerType{value: 2},
        %Symbol{name: :y}
      ]
    }

    result = PatternDeconstructor.deconstruct(ir)

    expected = [
      [
        %TupleAccess{index: 0},
        %Symbol{name: :x}
      ],
      [
        %TupleAccess{index: 2},
        %Symbol{name: :y}
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

    assert PatternDeconstructor.deconstruct(ir) == []
  end

  test "nested tuple with single var" do
    ir = %TupleType{
      data: [
        %IntegerType{value: 1},
        %TupleType{
          data: [
            %Symbol{name: :x},
            %IntegerType{value: 2}
          ]
        }
      ]
    }

    result = PatternDeconstructor.deconstruct(ir)

    expected = [
      [
        %TupleAccess{index: 1},
        %TupleAccess{index: 0},
        %Symbol{name: :x}
      ]
    ]

    assert result == expected
  end

  test "nested tuple with multiple vars" do
    ir = %TupleType{
      data: [
        %IntegerType{value: 1},
        %Symbol{name: :x},
        %TupleType{
          data: [
            %Symbol{name: :y},
            %IntegerType{value: 2}
          ]
        }
      ]
    }

    result = PatternDeconstructor.deconstruct(ir)

    expected = [
      [
        %TupleAccess{index: 1},
        %Symbol{name: :x}
      ],
      [
        %TupleAccess{index: 2},
        %TupleAccess{index: 0},
        %Symbol{name: :y}
      ]
    ]

    assert result == expected
  end
end
