defmodule Hologram.Compiler.PatternDeconstructor.ConsOperatorTest do
  use Hologram.Test.UnitCase, async: false

  alias Hologram.Compiler.IR.ConsOperator
  alias Hologram.Compiler.IR.IntegerType
  alias Hologram.Compiler.IR.ListIndexAccess
  alias Hologram.Compiler.IR.ListTailAccess
  alias Hologram.Compiler.IR.ListType
  alias Hologram.Compiler.IR.Variable
  alias Hologram.Compiler.PatternDeconstructor

  test "non-nested cons operator without vars" do
    # [1 | [2, 3]]

    ir = %ConsOperator{
      head: %IntegerType{value: 1},
      tail: %ListType{
        data: [
          %IntegerType{value: 2},
          %IntegerType{value: 3}
        ]
      }
    }

    assert PatternDeconstructor.deconstruct(ir) == []
  end

  test "non-nested cons operator with head var" do
    # [x | [1, 2]]

    ir = %ConsOperator{
      head: %Variable{name: :x},
      tail: %ListType{
        data: [
          %IntegerType{value: 1},
          %IntegerType{value: 2}
        ]
      }
    }

    result = PatternDeconstructor.deconstruct(ir)

    expected = [
      [
        %ListIndexAccess{index: 0},
        %Variable{name: :x}
      ]
    ]

    assert result == expected
  end

  test "non-nested cons operator with tail var" do
    # [1 | x]

    ir = %ConsOperator{
      head: %IntegerType{value: 1},
      tail: %Variable{name: :x}
    }

    result = PatternDeconstructor.deconstruct(ir)

    expected = [
      [
        %ListTailAccess{},
        %Variable{name: :x}
      ]
    ]

    assert result == expected
  end

  test "non-nested cons operator with head and tail vars" do
    # [x | y]

    ir = %ConsOperator{
      head: %Variable{name: :x},
      tail: %Variable{name: :y}
    }

    result = PatternDeconstructor.deconstruct(ir)

    expected = [
      [
        %ListIndexAccess{index: 0},
        %Variable{name: :x}
      ],
      [
        %ListTailAccess{},
        %Variable{name: :y}
      ]
    ]

    assert result == expected
  end

  test "nested cons operator without vars" do
    # [1 | [2 | [3, 4]]]

    ir = %ConsOperator{
      head: %IntegerType{value: 1},
      tail: %ConsOperator{
        head: %IntegerType{value: 2},
        tail: %ListType{
          data: [
            %IntegerType{value: 3},
            %IntegerType{value: 4}
          ]
        }
      }
    }

    assert PatternDeconstructor.deconstruct(ir) == []
  end

  test "nested cons operator with vars in heads" do
    # [x | [y | [3, 4]]]

    ir = %ConsOperator{
      head: %Variable{name: :x},
      tail: %ConsOperator{
        head: %Variable{name: :y},
        tail: %ListType{
          data: [
            %IntegerType{value: 3},
            %IntegerType{value: 4}
          ]
        }
      }
    }

    result = PatternDeconstructor.deconstruct(ir)

    expected = [
      [
        %ListIndexAccess{index: 0},
        %Variable{name: :x}
      ],
      [
        %ListTailAccess{},
        %ListIndexAccess{index: 0},
        %Variable{name: :y}
      ]
    ]

    assert result == expected
  end

  test "nested cons operator with vars in most-nested tail" do
    # [1 | [2 | [x, y]]]

    ir = %ConsOperator{
      head: %IntegerType{value: 1},
      tail: %ConsOperator{
        head: %IntegerType{value: 2},
        tail: %ListType{
          data: [
            %Variable{name: :x},
            %Variable{name: :y}
          ]
        }
      }
    }

    result = PatternDeconstructor.deconstruct(ir)

    expected = [
      [
        %ListTailAccess{},
        %ListTailAccess{},
        %ListIndexAccess{index: 0},
        %Variable{name: :x}
      ],
      [
        %ListTailAccess{},
        %ListTailAccess{},
        %ListIndexAccess{index: 1},
        %Variable{name: :y}
      ]
    ]

    assert result == expected
  end
end
