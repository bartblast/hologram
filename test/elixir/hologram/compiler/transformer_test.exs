defmodule Hologram.Compiler.TransformerTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.Transformer

  alias Hologram.Compiler.IR

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

  describe "module attribute operator" do
    test "AST obtained directly from source file" do
      # @my_attr
      ast = {:@, [line: 1], [{:my_attr, [line: 1], nil}]}

      assert transform(ast) == %IR.ModuleAttributeOperator{name: :my_attr}
    end

    test "AST returned from macro" do
      # apply(Module1, :"MACRO-macro_module_attribute_operator_1", [__ENV__])
      ast =
        {:@, [context: Module1, imports: [{1, Kernel}]],
         [{:my_attr, [context: Module1], Module1}]}

      assert transform(ast) == %IR.ModuleAttributeOperator{name: :my_attr}
    end
  end
end
