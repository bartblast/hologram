defmodule Hologram.Compiler.TransformerTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.Transformer

  alias Hologram.Compiler.IR
  alias Hologram.Test.Fixtures.Compiler.Transformer.Module1

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

  describe "module attribute definition" do
    @expected_ir %IR.ModuleAttributeDefinition{
      name: :my_attr,
      expression: %IR.IntegerType{value: 987}
    }

    test "AST obtained directly from source file" do
      # @my_attr 987
      ast = {:@, [line: 1], [{:my_attr, [line: 1], [987]}]}

      assert transform(ast) == @expected_ir
    end

    test "AST returned from macro" do
      # apply(Module1, :"MACRO-macro_module_attribute_definition", [__ENV__])
      ast =
        {:@, [context: Module1, imports: [{1, Kernel}]], [{:my_attr, [context: Module1], [987]}]}

      assert transform(ast) == @expected_ir
    end
  end

  describe "module attribute operator" do
    @expected_ir %IR.ModuleAttributeOperator{name: :my_attr}

    test "AST obtained directly from source file" do
      # @my_attr
      ast = {:@, [line: 1], [{:my_attr, [line: 1], nil}]}

      assert transform(ast) == @expected_ir
    end

    test "AST returned from macro" do
      # apply(Module1, :"MACRO-macro_module_attribute_operator", [__ENV__])
      ast =
        {:@, [context: Module1, imports: [{1, Kernel}]],
         [{:my_attr, [context: Module1], Module1}]}

      assert transform(ast) == @expected_ir
    end
  end

  describe "symbol" do
    @expected_ir %IR.Symbol{name: :my_symbol}

    test "AST obtained directly from source file" do
      # my_symbol
      ast = {:my_symbol, [line: 1], nil}

      assert transform(ast) == @expected_ir
    end

    test "AST returned from macro" do
      # apply(Module1, :"MACRO-macro_symbol", [__ENV__])
      ast = {:my_symbol, [], Module1}

      assert transform(ast) == @expected_ir
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
end
