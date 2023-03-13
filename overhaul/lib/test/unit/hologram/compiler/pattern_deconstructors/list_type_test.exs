defmodule Hologram.Compiler.PatternDeconstructor.ListTypeTest do
  use Hologram.Test.UnitCase, async: false

  alias Hologram.Compiler.IR.IntegerType
  alias Hologram.Compiler.IR.ListIndexAccess
  alias Hologram.Compiler.IR.ListType
  alias Hologram.Compiler.IR.Symbol
  alias Hologram.Compiler.PatternDeconstructor

  test "non-nested list without vars" do
    ir = %ListType{
      data: [
        %IntegerType{value: 1},
        %IntegerType{value: 2}
      ]
    }

    assert PatternDeconstructor.deconstruct(ir) == []
  end

  test "non-nested list with single var" do
    ir = %ListType{
      data: [
        %IntegerType{value: 1},
        %Symbol{name: :x}
      ]
    }

    result = PatternDeconstructor.deconstruct(ir)

    expected = [
      [
        %ListIndexAccess{index: 1},
        %Symbol{name: :x}
      ]
    ]

    assert result == expected
  end

  test "non-nested list with multiple vars" do
    ir = %ListType{
      data: [
        %Symbol{name: :x},
        %IntegerType{value: 2},
        %Symbol{name: :y}
      ]
    }

    result = PatternDeconstructor.deconstruct(ir)

    expected = [
      [
        %ListIndexAccess{index: 0},
        %Symbol{name: :x}
      ],
      [
        %ListIndexAccess{index: 2},
        %Symbol{name: :y}
      ]
    ]

    assert result == expected
  end

  test "nested list without vars" do
    ir = %ListType{
      data: [
        %IntegerType{value: 1},
        %IntegerType{value: 2},
        %ListType{
          data: [
            %IntegerType{value: 3},
            %IntegerType{value: 4}
          ]
        }
      ]
    }

    assert PatternDeconstructor.deconstruct(ir) == []
  end

  test "nested list with single var" do
    ir = %ListType{
      data: [
        %IntegerType{value: 1},
        %ListType{
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
        %ListIndexAccess{index: 1},
        %ListIndexAccess{index: 0},
        %Symbol{name: :x}
      ]
    ]

    assert result == expected
  end

  test "nested list with multiple vars" do
    ir = %ListType{
      data: [
        %IntegerType{value: 1},
        %Symbol{name: :x},
        %ListType{
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
        %ListIndexAccess{index: 1},
        %Symbol{name: :x}
      ],
      [
        %ListIndexAccess{index: 2},
        %ListIndexAccess{index: 0},
        %Symbol{name: :y}
      ]
    ]

    assert result == expected
  end
end
