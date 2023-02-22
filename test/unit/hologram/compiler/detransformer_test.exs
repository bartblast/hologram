defmodule Hologram.Compiler.DetransformerTest do
  use Hologram.Test.UnitCase, async: true
  import Hologram.Compiler.Detransformer
  alias Hologram.Compiler.IR

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

  test "map" do
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

  # --- OVERHAUL ---

  # test "(elixir) list" do
  #   ir = [%IR.IntegerType{value: 1}, %IR.IntegerType{value: 2}]
  #   result = Detransformer.detransform(ir)

  #   assert result == [1, 2]
  # end

  # describe "data types" do
  #   test "list" do
  #     ir = %IR.ListType{
  #       data: [
  #         %IR.AtomType{value: :a},
  #         %IR.IntegerType{value: 1}
  #       ]
  #     }

  #     result = Detransformer.detransform(ir)
  #     expected = [:a, 1]

  #     assert result == expected
  #   end

  #   test "struct" do
  #     ir = %IR.StructType{
  #       module: %IR.ModuleType{
  #         module: Hologram.Test.Fixtures.Struct,
  #         segments: [:Hologram, :Test, :Fixtures, :Struct]
  #       },
  #       data: [
  #         {%IR.AtomType{value: :a}, %IR.IntegerType{value: 1}},
  #         {%IR.AtomType{value: :b}, %IR.IntegerType{value: 2}}
  #       ]
  #     }

  #     result = Detransformer.detransform(ir)
  #     expected = {:%{}, [], [__struct__: Hologram.Test.Fixtures.Struct, a: 1, b: 2]}

  #     assert result == expected
  #   end
  # end

  # test "addition operator" do
  #   left = %IR.IntegerType{value: 1}
  #   right = %IR.IntegerType{value: 2}
  #   ir = %IR.AdditionOperator{left: left, right: right}

  #   result = Detransformer.detransform(ir)
  #   expected = {:+, [line: 0], [1, 2]}

  #   assert result == expected
  # end

  # test "equal to operator" do
  #   left = %IR.IntegerType{value: 1}
  #   right = %IR.IntegerType{value: 2}
  #   ir = %IR.EqualToOperator{left: left, right: right}

  #   result = Detransformer.detransform(ir)
  #   expected = {:==, [line: 0], [1, 2]}

  #   assert result == expected
  # end

  # test "function call" do
  #   module = %IR.ModuleType{module: A.B, segments: [:A, :B]}
  #   args = [%IR.IntegerType{value: 1}, %IR.IntegerType{value: 2}]
  #   ir = %IR.FunctionCall{module: module, function: :my_fun, args: args}
  #   result = Detransformer.detransform(ir)

  #   expected =
  #     {{:., [line: 0], [{:__aliases__, [line: 0], [:A, :B]}, :my_fun]}, [line: 0], [1, 2]}

  #   assert result == expected
  # end

  # test "variable" do
  #   ir = %IR.Variable{name: :test}
  #   result = Detransformer.detransform(ir)
  #   assert result == {:test, [line: 0], nil}
  # end
end
