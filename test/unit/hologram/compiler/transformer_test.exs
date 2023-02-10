defmodule Hologram.Compiler.TransformerTest do
  use Hologram.Test.UnitCase, async: true
  import Hologram.Compiler.Transformer
  alias Hologram.Compiler.IR

  # --- DATA TYPES --

  test "boolean type" do
    ast = ast("true")
    assert transform(ast) == %IR.BooleanType{value: true}
  end

  test "float type" do
    ast = ast("1.0")
    assert transform(ast) == %IR.FloatType{value: 1.0}
  end

  test "integer type" do
    ast = ast("1")
    assert transform(ast) == %IR.IntegerType{value: 1}
  end

  test "nil type" do
    ast = ast("nil")
    assert transform(ast) == %IR.NilType{}
  end

  test "string type" do
    ast = ast(~s("test"))
    assert transform(ast) == %IR.StringType{value: "test"}
  end
end
