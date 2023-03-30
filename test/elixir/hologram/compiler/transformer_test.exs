defmodule Hologram.Compiler.TransformerTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.Transformer
  alias Hologram.Compiler.IR

  describe "anonymous function call" do
    test "without args" do
      # test.()
      ast = {{:., [line: 1], [{:test, [line: 1], nil}]}, [line: 1], []}

      assert transform(ast) == %IR.AnonymousFunctionCall{
               function: %IR.Variable{name: :test},
               args: []
             }
    end

    test "with args" do
      # test.(1, 2)
      ast = {{:., [line: 1], [{:test, [line: 1], nil}]}, [line: 1], [1, 2]}

      assert transform(ast) == %IR.AnonymousFunctionCall{
               function: %IR.Variable{name: :test},
               args: [
                 %IR.IntegerType{value: 1},
                 %IR.IntegerType{value: 2}
               ]
             }
    end
  end

  describe "atom type" do
    test "boolean" do
      # true
      ast = true

      assert transform(ast) == %IR.AtomType{value: true}
    end

    test "nil" do
      # nil
      ast = nil

      assert transform(ast) == %IR.AtomType{value: nil}
    end

    test "other than boolean or nil" do
      # :test
      ast = :test

      assert transform(ast) == %IR.AtomType{value: :test}
    end
  end

  test "dot operator" do
    # abc.x
    ast = {{:., [line: 1], [{:abc, [line: 1], nil}, :x]}, [no_parens: true, line: 1], []}

    assert transform(ast) == %IR.DotOperator{
             left: %IR.Variable{name: :abc},
             right: %IR.AtomType{value: :x}
           }
  end

  test "float type" do
    # 1.0
    ast = 1.0

    assert transform(ast) == %IR.FloatType{value: 1.0}
  end

  test "integer type" do
    # 1
    ast = 1

    assert transform(ast) == %IR.IntegerType{value: 1}
  end

  test "list type" do
    # [1, 2]
    ast = [1, 2]

    assert transform(ast) == %IR.ListType{
             data: [
               %IR.IntegerType{value: 1},
               %IR.IntegerType{value: 2}
             ]
           }
  end

  describe "local function call" do
    test "without args" do
      # my_fun()
      ast = {:my_fun, [line: 1], []}

      assert transform(ast) == %IR.LocalFunctionCall{function: :my_fun, args: []}
    end

    test "with args" do
      # my_fun(1, 2)
      ast = {:my_fun, [line: 1], [1, 2]}

      assert transform(ast) == %IR.LocalFunctionCall{
               function: :my_fun,
               args: [
                 %IR.IntegerType{value: 1},
                 %IR.IntegerType{value: 2}
               ]
             }
    end
  end

  test "module attribute operator" do
    # @my_attr
    ast = {:@, [line: 1], [{:my_attr, [line: 1], nil}]}

    assert transform(ast) == %IR.ModuleAttributeOperator{name: :my_attr}
  end

  describe "module type" do
    test "when first alias segment is not 'Elixir'" do
      # Aaa.Bbb
      ast = {:__aliases__, [line: 1], [:Aaa, :Bbb]}

      assert transform(ast) == %IR.ModuleType{module: Aaa.Bbb, segments: [:Aaa, :Bbb]}
    end

    test "when first alias segment is 'Elixir'" do
      # Elixir.Aaa.Bbb
      ast = {:__aliases__, [line: 1], [Elixir, :Aaa, :Bbb]}

      assert transform(ast) == %IR.ModuleType{module: Aaa.Bbb, segments: [:Aaa, :Bbb]}
    end
  end

  describe "tuple type" do
    test "2-element tuple" do
      # {1, 2}
      ast = {1, 2}

      assert transform(ast) == %IR.TupleType{
               data: [
                 %IR.IntegerType{value: 1},
                 %IR.IntegerType{value: 2}
               ]
             }
    end

    test "non-2-element tuple" do
      # {1, 2, 3}
      ast = {:{}, [line: 1], [1, 2, 3]}

      assert transform(ast) == %IR.TupleType{
               data: [
                 %IR.IntegerType{value: 1},
                 %IR.IntegerType{value: 2},
                 %IR.IntegerType{value: 3}
               ]
             }
    end
  end

  test "variable" do
    # my_var
    ast = {:my_var, [line: 1], nil}

    assert transform(ast) == %IR.Variable{name: :my_var}
  end
end
