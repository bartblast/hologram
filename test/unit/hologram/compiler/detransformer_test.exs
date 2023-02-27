defmodule Hologram.Compiler.DetransformerTest do
  use Hologram.Test.UnitCase, async: true
  import Hologram.Compiler.Detransformer
  alias Hologram.Compiler.IR

  # --- OPERATORS ---

  test "access operator" do
    # a[:b]
    ir = %IR.AccessOperator{
      data: %IR.Variable{name: :a},
      key: %IR.AtomType{value: :b}
    }

    assert detransform(ir) ==
             {{:., [line: 0], [{:__aliases__, [alias: false], [:Access]}, :get]}, [line: 0],
              [{:a, [line: 0], nil}, :b]}
  end

  test "addition operator" do
    # 1 + 2
    ir = %IR.AdditionOperator{left: %IR.IntegerType{value: 1}, right: %IR.IntegerType{value: 2}}

    assert detransform(ir) == {:+, [line: 0], [1, 2]}
  end

  test "cons operator" do
    # [h | t]
    ir = %IR.ConsOperator{
      head: %IR.Variable{name: :h},
      tail: %IR.Variable{name: :t}
    }

    assert detransform(ir) == [{:|, [line: 0], [{:h, [line: 0], nil}, {:t, [line: 0], nil}]}]
  end

  test "division operator" do
    # 1 / 2
    ir = %IR.DivisionOperator{left: %IR.IntegerType{value: 1}, right: %IR.IntegerType{value: 2}}

    assert detransform(ir) == {:/, [line: 0], [1, 2]}
  end

  test "dot operator" do
    # my_map.my_key
    ir = %IR.DotOperator{left: %IR.Variable{name: :my_map}, right: %IR.AtomType{value: :my_key}}

    assert detransform(ir) ==
             {{:., [line: 0], [{:my_map, [line: 0], nil}, :my_key]}, [no_parens: true, line: 0],
              []}
  end

  test "equal to operator" do
    # 1 == 2
    ir = %IR.EqualToOperator{left: %IR.IntegerType{value: 1}, right: %IR.IntegerType{value: 2}}

    assert detransform(ir) == {:==, [line: 0], [1, 2]}
  end

  test "less than to operator" do
    # 1 < 2
    ir = %IR.LessThanOperator{left: %IR.IntegerType{value: 1}, right: %IR.IntegerType{value: 2}}

    assert detransform(ir) == {:<, [line: 0], [1, 2]}
  end

  test "list concatenation operator" do
    # [1, 2] ++ [3, 4]
    ir = %IR.ListConcatenationOperator{
      left: %IR.ListType{
        data: [
          %IR.IntegerType{value: 1},
          %IR.IntegerType{value: 2}
        ]
      },
      right: %IR.ListType{
        data: [
          %IR.IntegerType{value: 3},
          %IR.IntegerType{value: 4}
        ]
      }
    }

    assert detransform(ir) == {:++, [line: 0], [[1, 2], [3, 4]]}
  end

  test "list subtraction operator" do
    # [1, 2] -- [3, 4]
    ir = %IR.ListSubtractionOperator{
      left: %IR.ListType{
        data: [
          %IR.IntegerType{value: 1},
          %IR.IntegerType{value: 2}
        ]
      },
      right: %IR.ListType{
        data: [
          %IR.IntegerType{value: 3},
          %IR.IntegerType{value: 4}
        ]
      }
    }

    assert detransform(ir) == {:--, [line: 0], [[1, 2], [3, 4]]}
  end

  test "match operator" do
    # x = 123
    ir = %IR.MatchOperator{
      bindings: [
        %IR.Binding{
          name: :x,
          access_path: [%Hologram.Compiler.IR.MatchAccess{}]
        }
      ],
      left: %IR.Variable{name: :x},
      right: %IR.IntegerType{value: 123}
    }

    assert detransform(ir) == {:=, [line: 0], [{:x, [line: 0], nil}, 123]}
  end

  test "membership operator" do
    # 1 in [2, 3]
    ir = %IR.MembershipOperator{
      left: %IR.IntegerType{value: 1},
      right: %IR.ListType{
        data: [
          %IR.IntegerType{value: 2},
          %IR.IntegerType{value: 3}
        ]
      }
    }

    assert detransform(ir) == {:in, [line: 0], [1, [2, 3]]}
  end

  test "module attribute operator" do
    # @a
    ir = %IR.ModuleAttributeOperator{name: :a}

    assert detransform(ir) == {:@, [line: 0], [{:a, [line: 0], nil}]}
  end

  # --- DATA TYPES ---

  test "atom type" do
    # :abc
    ir = %IR.AtomType{value: :abc}

    assert detransform(ir) == :abc
  end

  test "boolean type" do
    # true
    ir = %IR.BooleanType{value: true}

    assert detransform(ir) == true
  end

  test "float type" do
    # 1.23
    ir = %IR.FloatType{value: 1.23}

    assert detransform(ir) == 1.23
  end

  test "integer type" do
    # 123
    ir = %IR.IntegerType{value: 123}

    assert detransform(ir) == 123
  end

  test "list type" do
    # [1, :b]
    ir = %IR.ListType{data: [%IR.IntegerType{value: 1}, %IR.AtomType{value: :b}]}

    assert detransform(ir) == [1, :b]
  end

  test "map type" do
    # %{a: 1, b: 2}
    ir = %IR.MapType{
      data: [
        {%IR.AtomType{value: :a}, %IR.IntegerType{value: 1}},
        {%IR.AtomType{value: :b}, %IR.IntegerType{value: 2}}
      ]
    }

    assert detransform(ir) == {:%{}, [line: 0], [a: 1, b: 2]}
  end

  test "module type" do
    # A.B
    ir = %IR.ModuleType{module: A.B, segments: [:A, :B]}

    assert detransform(ir) == {:__aliases__, [line: 0], [:A, :B]}
  end

  test "nil type" do
    # nil
    ir = %IR.NilType{}

    assert detransform(ir) == nil
  end

  test "struct type" do
    # %Hologram.Test.Fixtures.Struct{a: 1, b: 2}
    ir = %IR.StructType{
      module: %IR.ModuleType{
        module: Hologram.Test.Fixtures.Struct,
        segments: [:Hologram, :Test, :Fixtures, :Struct]
      },
      data: [
        {%IR.AtomType{value: :a}, %IR.IntegerType{value: 1}},
        {%IR.AtomType{value: :b}, %IR.IntegerType{value: 2}}
      ]
    }

    assert detransform(ir) ==
             {:%, [line: 0],
              [
                {:__aliases__, [line: 0], [:Hologram, :Test, :Fixtures, :Struct]},
                {:%{}, [line: 0], [a: 1, b: 2]}
              ]}
  end

  # --- CONTROL FLOW ---

  test "function call" do
    # A.B.my_fun(1, 2)
    module = %IR.ModuleType{module: A.B, segments: [:A, :B]}
    args = [%IR.IntegerType{value: 1}, %IR.IntegerType{value: 2}]
    ir = %IR.FunctionCall{module: module, function: :my_fun, args: args}

    assert detransform(ir) ==
             {{:., [line: 0], [{:__aliases__, [line: 0], [:A, :B]}, :my_fun]}, [line: 0], [1, 2]}
  end

  test "variable" do
    # test
    ir = %IR.Variable{name: :test}

    assert detransform(ir) == {:test, [line: 0], nil}
  end
end
