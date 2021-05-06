# TODO: refactor

defmodule Hologram.Compiler.TransformerTest do
  use ExUnit.Case, async: true

  import Hologram.Compiler.Parser, only: [parse!: 1]

  alias Hologram.Compiler.AST.{AtomType, BooleanType, IntegerType, MapType, StringType}
  alias Hologram.Compiler.AST.MatchOperator
  alias Hologram.Compiler.AST.MapAccess
  alias Hologram.Compiler.AST.{Alias, Import, ModuleAttributeOperator, Variable}
  alias Hologram.Compiler.Transformer
  alias TestModule1
  alias TestModule4

  describe "primitive types" do
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

  describe "other" do
    test "import" do
      result =
        parse!("import Prefix.Test")
        |> Transformer.transform()

      expected = %Import{module: [:Prefix, :Test]}

      assert result == expected
    end

    test "alias" do
      result =
        parse!("alias Prefix.Test")
        |> Transformer.transform()

      expected = %Alias{module: [:Prefix, :Test], as: [:Test]}

      assert result == expected
    end

    test "variable" do
      ast = parse!("x")
      assert Transformer.transform(ast) == %Variable{name: :x}
    end

    test "module attribute" do
      ast = parse!("@x")
      assert Transformer.transform(ast) == %ModuleAttributeOperator{name: :x}
    end
  end
end
