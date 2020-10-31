defmodule Reflex.TranspilerTest do
  use ExUnit.Case
  alias Reflex.Transpiler

  describe "meta/1" do
    test "string" do
      assert Transpiler.meta("test") == {:string, "test"}
    end

    test "integer" do
      assert Transpiler.meta(123) == {:integer, 123}
    end
  end

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
    test "string" do
      ast = Transpiler.parse!("\"test\"")
      assert Transpiler.transpile(ast) == {:string, "test"}
    end

    test "integer" do
      ast = Transpiler.parse!("1")
      assert Transpiler.transpile(ast) == {:integer, 1}
    end

    test "boolean" do
      ast = Transpiler.parse!("true")
      assert Transpiler.transpile(ast) == {:boolean, true}
    end

    test "if" do
      ast = Transpiler.parse!("if true, do: 1, else: 2")
      assert Transpiler.transpile(ast) == {:if, {{:boolean, true}, {:integer, 1}, {:integer, 2}}}
    end
  end
end
