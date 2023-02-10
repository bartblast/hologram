defmodule Hologram.Compiler.TransformerTest do
  use Hologram.Test.UnitCase, async: true
  import Hologram.Compiler.Transformer
  alias Hologram.Compiler.IR

  describe "data types" do
    test "boolean" do
      ast = ast("true")
      assert transform(ast) == %IR.BooleanType{value: true}
    end

    test "float" do
      ast = ast("1.0")
      assert transform(ast) == %IR.FloatType{value: 1.0}
    end

    test "integer" do
      ast = ast("1")
      assert transform(ast) == %IR.IntegerType{value: 1}
    end

    test "nil" do
      ast = ast("nil")
      assert transform(ast) == %IR.NilType{}
    end

    test "string" do
      ast = ast(~s("test"))
      assert transform(ast) == %IR.StringType{value: "test"}
    end
  end
end
