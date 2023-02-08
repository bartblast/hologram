defmodule Hologram.Compiler.DetransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.Detransformer
  alias Hologram.Compiler.IR

  test "(elixir) list" do
    ir = [%IR.IntegerType{value: 1}, %IR.IntegerType{value: 2}]
    result = Detransformer.detransform(ir)

    assert result == [1, 2]
  end

  describe "data types" do
    test "basic (atom, boolean, float, integer, string)" do
      ir = %IR.IntegerType{value: 123}
      result = Detransformer.detransform(ir)
      assert result == 123
    end

    test "list" do
      ir = %IR.ListType{
        data: [
          %IR.AtomType{value: :a},
          %IR.IntegerType{value: 1}
        ]
      }

      result = Detransformer.detransform(ir)
      expected = [:a, 1]

      assert result == expected
    end

    test "module" do
      ir = %IR.ModuleType{module: A.B, segments: [:A, :B]}

      result = Detransformer.detransform(ir)
      expected = {:__aliases__, [line: 0], [:A, :B]}

      assert result == expected
    end

    test "nil" do
      ir = %IR.NilType{}
      result = Detransformer.detransform(ir)
      assert result == nil
    end

    test "struct" do
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

      result = Detransformer.detransform(ir)
      expected = {:%{}, [], [__struct__: Hologram.Test.Fixtures.Struct, a: 1, b: 2]}

      assert result == expected
    end
  end

  test "addition operator" do
    left = %IR.IntegerType{value: 1}
    right = %IR.IntegerType{value: 2}
    ir = %IR.AdditionOperator{left: left, right: right}

    result = Detransformer.detransform(ir)
    expected = {:+, [line: 0], [1, 2]}

    assert result == expected
  end

  test "function call" do
    module = %IR.ModuleType{module: A.B, segments: [:A, :B]}
    args = [%IR.IntegerType{value: 1}, %IR.IntegerType{value: 2}]
    ir = %IR.FunctionCall{module: module, function: :my_fun, args: args}
    result = Detransformer.detransform(ir)

    expected =
      {{:., [line: 0], [{:__aliases__, [line: 0], [:A, :B]}, :my_fun]}, [line: 0], [1, 2]}

    assert result == expected
  end

  test "variable" do
    ir = %IR.Variable{name: :test}
    result = Detransformer.detransform(ir)
    assert result == {:test, [line: 0], nil}
  end
end
