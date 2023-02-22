defmodule Hologram.Compiler.DetransformerTest do
  use Hologram.Test.UnitCase, async: true
  import Hologram.Compiler.Detransformer
  alias Hologram.Compiler.IR

  # --- OPERATORS ---

  test "addition operator" do
    ir = %IR.AdditionOperator{left: %IR.IntegerType{value: 1}, right: %IR.IntegerType{value: 2}}

    assert detransform(ir) == {:+, [line: 0], [1, 2]}
  end

  test "equal to operator" do
    ir = %IR.EqualToOperator{left: %IR.IntegerType{value: 1}, right: %IR.IntegerType{value: 2}}

    assert detransform(ir) == {:==, [line: 0], [1, 2]}
  end

  # --- DATA TYPES ---

  test "atom type" do
    ir = %IR.AtomType{value: :abc}

    assert detransform(ir) == :abc
  end

  test "boolean type" do
    ir = %IR.BooleanType{value: true}

    assert detransform(ir) == true
  end

  test "float type" do
    ir = %IR.FloatType{value: 1.23}

    assert detransform(ir) == 1.23
  end

  test "integer type" do
    ir = %IR.IntegerType{value: 123}

    assert detransform(ir) == 123
  end

  test "list type" do
    ir = %IR.ListType{data: [%IR.IntegerType{value: 1}, %IR.AtomType{value: :b}]}

    assert detransform(ir) == [1, :b]
  end

  test "map type" do
    ir = %IR.MapType{
      data: [
        {%IR.AtomType{value: :a}, %IR.IntegerType{value: 1}},
        {%IR.AtomType{value: :b}, %IR.IntegerType{value: 2}}
      ]
    }

    assert detransform(ir) == {:%{}, [], [a: 1, b: 2]}
  end

  test "module type" do
    ir = %IR.ModuleType{module: A.B, segments: [:A, :B]}

    assert detransform(ir) == {:__aliases__, [line: 0], [:A, :B]}
  end

  test "nil type" do
    ir = %IR.NilType{}

    assert detransform(ir) == nil
  end

  test "struct type" do
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

    assert detransform(ir) == {:%{}, [], [__struct__: Hologram.Test.Fixtures.Struct, a: 1, b: 2]}
  end

  # --- CONTROL-FLOW ---

  test "function call" do
    module = %IR.ModuleType{module: A.B, segments: [:A, :B]}
    args = [%IR.IntegerType{value: 1}, %IR.IntegerType{value: 2}]
    ir = %IR.FunctionCall{module: module, function: :my_fun, args: args}

    assert detransform(ir) ==
             {{:., [line: 0], [{:__aliases__, [line: 0], [:A, :B]}, :my_fun]}, [line: 0], [1, 2]}
  end

  test "variable" do
    ir = %IR.Variable{name: :test}

    assert detransform(ir) == {:test, [line: 0], nil}
  end
end
