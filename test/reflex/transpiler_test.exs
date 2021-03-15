defmodule Reflex.TranspilerTest do
  use ExUnit.Case
  alias Reflex.Transpiler

  describe "aggregate_assignments/2" do
    test "var" do
      result =
        Transpiler.parse!("x")
        |> Transpiler.transform()
        |> Transpiler.aggregate_assignments()

      assert result == [[:x]]
    end

    test "map, root keys" do
      result =
        Transpiler.parse!("%{a: x, b: y}")
        |> Transpiler.transform()
        |> Transpiler.aggregate_assignments()

      assert result == [
        [:x, [:map_access, :a]],
        [:y, [:map_access, :b]]
      ]
    end

    test "map, nested keys" do
      result =
        Transpiler.parse!("%{a: 1, b: %{p: x, r: 4}, c: 3, d: %{m: 0, n: y}}")
        |> Transpiler.transform()
        |> Transpiler.aggregate_assignments()

      assert result ==
        [
          [:x, [:map_access, :b], [:map_access, :p]],
          [:y, [:map_access, :d], [:map_access, :n]]
        ]
    end

    test "map, root and nested keys" do
      result =
        Transpiler.parse!("%{a: 1, b: %{p: x, r: 4}, c: z, d: %{m: 0, n: y}}")
        |> Transpiler.transform()
        |> Transpiler.aggregate_assignments()

      assert result ==
        [
          [:x, [:map_access, :b], [:map_access, :p]],
          [:z, [:map_access, :c]],
          [:y, [:map_access, :d], [:map_access, :n]]
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
      assert {:ok, _} = Transpiler.parse_file("lib/demo/reflex/transpiler.ex")
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

    test "assignment simple" do
      ast = Transpiler.parse!("x = 1")
      assert Transpiler.transform(ast) == {:assignment, [[:x]], {:integer, 1}}
    end

    test "assignment complex" do
      result =
        Transpiler.parse!("%{a: x, b: y} = %{a: 1, b: 2}")
        |> Transpiler.transform()

      assert result == {
        :assignment,
        [
          [:x, [:map_access, :a]],
          [:y, [:map_access, :b]]
        ],
        {:map, [a: {:integer, 1}, b: {:integer, 2}]},
      }
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

    test "case" do
      ast = Transpiler.parse!("case x do 1 -> :result_1; 2 -> :result_2 end")
      result = Transpiler.transform(ast)

      expected = {
        :case,
        {:var, :x},
        [
          {:clause, {:integer, 1}, {:atom, :result_1}},
          {:clause, {:integer, 2}, {:atom, :result_2}}
        ]
      }

      assert result == expected
    end
  end
end
