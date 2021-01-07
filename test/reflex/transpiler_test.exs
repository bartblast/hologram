defmodule Reflex.TranspilerTest do
  use ExUnit.Case
  alias Reflex.Transpiler

  describe "aggregate_assignments/2" do
    test "var" do
      result =
        Transpiler.parse!("x")
        |> Transpiler.transform()
        |> Transpiler.aggregate_assignments()

      assert result == [[[:x, :assign]]]
    end

    test "map, root keys" do
      result =
        Transpiler.parse!("%{a: x, b: y}")
        |> Transpiler.transform()
        |> Transpiler.aggregate_assignments()

      assert result == [
        [[:map_access, :a], [:x, :assign]],
        [[:map_access, :b], [:y, :assign]]
      ]
    end

    test "map, nested keys" do
      result =
        Transpiler.parse!("%{a: 1, b: %{p: x, r: 4}, c: 3, d: %{m: 0, n: y}}")
        |> Transpiler.transform()
        |> Transpiler.aggregate_assignments()

      assert result ==
        [
          [[:map_access, :b], [:map_access, :p], [:x, :assign]],
          [[:map_access, :d], [:map_access, :n], [:y, :assign]]
        ]
    end

    test "map, root and nested keys" do
      result =
        Transpiler.parse!("%{a: 1, b: %{p: x, r: 4}, c: z, d: %{m: 0, n: y}}")
        |> Transpiler.transform()
        |> Transpiler.aggregate_assignments()

      assert result ==
        [
          [[:map_access, :b], [:map_access, :p], [:x, :assign]],
          [[:map_access, :c], [:z, :assign]],
          [[:map_access, :d], [:map_access, :n], [:y, :assign]]
        ]
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

  describe "transform/1" do
    test "string" do
      ast = Transpiler.parse!("\"test\"")
      assert Transpiler.transform(ast) == {:string, "test"}
    end

    test "integer" do
      ast = Transpiler.parse!("1")
      assert Transpiler.transform(ast) == {:integer, 1}
    end

    test "boolean" do
      ast = Transpiler.parse!("true")
      assert Transpiler.transform(ast) == {:boolean, true}
    end

    test "atom" do
      ast = Transpiler.parse!(":test")
      assert Transpiler.transform(ast) == {:atom, :test}
    end

    test "map" do
      ast = Transpiler.parse!("%{a: 1, b: 2}")
      assert Transpiler.transform(ast) == {:map, [a: {:integer, 1}, b: {:integer, 2}]}
    end

    test "destructure" do
      ast = Transpiler.parse!("head | tail")
      assert Transpiler.transform(ast) == {:destructure, {{:var, :head}, {:var, :tail}}}
    end

    test "var" do
      ast = Transpiler.parse!("x")
      assert Transpiler.transform(ast) == {:var, :x}
    end

    test "map with var match" do
      ast = Transpiler.parse!("%{a: 1, b: x}")
      assert Transpiler.transform(ast) == {:map, [a: {:integer, 1}, b: {:var, :x}]}
    end

    test "if" do
      ast = Transpiler.parse!("if true, do: 1, else: 2")
      assert Transpiler.transform(ast) == {:if, {{:boolean, true}, {:integer, 1}, {:integer, 2}}}
    end
  end
end
