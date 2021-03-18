defmodule Holograf.Transpiler.TransformerTest do
  use ExUnit.Case
  
  import Holograf.Transpiler.Parser, only: [parse!: 1]

  alias Holograf.Transpiler.AST.{AtomType, BooleanType, IntegerType, StringType}
  alias Holograf.Transpiler.Transformer

  describe "primitives" do
    test "atom" do
      ast = parse!(":test")
      assert Transformer.transform(ast) == %AtomType{value: :test}
    end

    test "boolean" do
      ast = parse!("true")
      assert Transformer.transform(ast) == %BooleanType{value: true}
    end

    test "integer" do
      ast = parse!("1")
      assert Transformer.transform(ast) == %IntegerType{value: 1}
    end

    test "string" do
      ast = parse!("\"test\"")
      assert Transformer.transform(ast) == %StringType{value: "test"}
    end
  end
end
