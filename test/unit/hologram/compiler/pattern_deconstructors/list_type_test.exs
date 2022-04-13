defmodule Hologram.Compiler.PatternDeconstructor.ListTypeTest do
  use Hologram.Test.UnitCase, async: false

  alias Hologram.Compiler.IR.IntegerType
  alias Hologram.Compiler.IR.ListIndexAccess
  alias Hologram.Compiler.IR.ListType
  alias Hologram.Compiler.IR.Variable
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
        %Variable{name: :x}
      ]
    }

    result = PatternDeconstructor.deconstruct(ir)

    expected = [
      [
        %ListIndexAccess{index: 1},
        %Variable{name: :x}
      ]
    ]

    assert result == expected
  end

  test "non-nested list with multiple vars" do
    ir = %ListType{
      data: [
        %Variable{name: :x},
        %IntegerType{value: 2},
        %Variable{name: :y}
      ]
    }

    result = PatternDeconstructor.deconstruct(ir)

    expected = [
      [
        %ListIndexAccess{index: 0},
        %Variable{name: :x}
      ],
      [
        %ListIndexAccess{index: 2},
        %Variable{name: :y}
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
            %Variable{name: :x},
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
        %Variable{name: :x}
      ]
    ]

    assert result == expected
  end

  test "nested list with multiple vars" do
    ir = %ListType{
      data: [
        %IntegerType{value: 1},
        %Variable{name: :x},
        %ListType{
          data: [
            %Variable{name: :y},
            %IntegerType{value: 2}
          ]
        }
      ]
    }

    result = PatternDeconstructor.deconstruct(ir)

    expected = [
      [
        %ListIndexAccess{index: 1},
        %Variable{name: :x}
      ],
      [
        %ListIndexAccess{index: 2},
        %ListIndexAccess{index: 0},
        %Variable{name: :y}
      ]
    ]

    assert result == expected
  end
end
