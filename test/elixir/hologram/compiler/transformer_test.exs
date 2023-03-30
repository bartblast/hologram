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
end
