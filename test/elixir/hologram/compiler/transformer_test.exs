defmodule Hologram.Compiler.TransformerTest do
  use Hologram.Test.UnitCase, async: true
  import Hologram.Compiler.Transformer

  alias Hologram.Compiler.IR
  alias Hologram.Test.Fixtures.Compiler.Transformer.Module2

  # --- DATA TYPES --

  test "atom type" do
    # :test
    ast = :test

    assert transform(ast) == %IR.AtomType{value: :test}
  end

  describe "binary type" do
    test "empty" do
      # <<>>
      ast = {:<<>>, [line: 1], []}

      assert transform(ast) == %IR.BinaryType{parts: []}
    end

    test "non-empty" do
      # <<1, 2>>
      ast = {:<<>>, [line: 1], [1, 2]}

      assert transform(ast) == %IR.BinaryType{
               parts: [
                 %IR.IntegerType{value: 1},
                 %IR.IntegerType{value: 2}
               ]
             }
    end
  end

  test "boolean type" do
    # true
    ast = true

    assert transform(ast) == %IR.BooleanType{value: true}
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

  test "nil type" do
    # nil
    ast = nil

    assert transform(ast) == %IR.NilType{}
  end

  test "string type" do
    # "test"
    ast = "test"

    assert transform(ast) == %IR.StringType{value: "test"}
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

  # --- CONTROL FLOW ---

  describe "alias" do
    test "non-contextual" do
      # Aaa.Bbb
      ast = {:__aliases__, [line: 1], [:Aaa, :Bbb]}

      assert transform(ast) == %IR.Alias{segments: [:Aaa, :Bbb]}
    end

    test "contextual, e.g. aliased inside a macro" do
      # {{:., [], [ast, :macro_2a]}, [], []} = apply(Module1, :"MACRO-macro_call_3", [__ENV__])
      ast = {:__aliases__, [alias: Module2], [:InnerAlias]}

      assert transform(ast) == %IR.ModuleType{
               module: Module2,
               segments: [:Hologram, :Test, :Fixtures, :Compiler, :Transformer, :Module2]
             }
    end
  end
end
