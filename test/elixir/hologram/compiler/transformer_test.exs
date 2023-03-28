defmodule Hologram.Compiler.TransformerTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.Transformer

  alias Hologram.Compiler.IR

  test "atom type" do
    # :test
    ast = :test

    assert transform(ast) == %IR.AtomType{value: :test}
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
end
