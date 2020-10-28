defmodule Reflex.TranspilerTest do
  use ExUnit.Case
  alias Reflex.Transpiler

  describe "parse!/1" do
    test "valid code" do
      assert Transpiler.parse!("1 + 2") == {:+, [line: 1], [1, 2]}
    end

    test "invalid code" do
      assert_raise RuntimeError, "Invalid code", fn ->
        Transpiler.parse!(".1")
      end
    end
  end

  describe "parse_file/1" do
    test "valid code" do
      assert {:ok, _} = Transpiler.parse_file("lib/reflex.ex")
    end

    test "invalid code" do
      assert {:error, _} = Transpiler.parse_file("README.md")
    end
  end

  describe "transpile/1" do
    test "string literal" do
      ast = Transpiler.parse!("\"test\"")
      assert Transpiler.transpile(ast) == "test"
    end

    test "integer literal" do
      ast = Transpiler.parse!("1")
      assert Transpiler.transpile(ast) == "1"
    end

    test "boolean literal" do
      ast = Transpiler.parse!("true")
      assert Transpiler.transpile(ast) == "true"
    end
  end
end
