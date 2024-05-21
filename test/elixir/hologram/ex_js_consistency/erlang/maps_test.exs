defmodule Hologram.ExJsConsistency.Erlang.MapsTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/maps_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  describe "fold/3" do
    @map %{1 => 1, 10 => 2, 100 => 3}

    setup do
      [fun: fn key, value, acc -> acc + key * value end]
    end

    test "reduces empty map", %{fun: fun} do
      assert :maps.fold(fun, 10, %{}) == 10
    end

    test "reduces non-empty map", %{fun: fun} do
      assert :maps.fold(fun, 10, @map) == 331
    end

    test "raises ArgumentError if the first argument is not an anonymous function" do
      assert_raise ArgumentError,
                   build_errors_found_msg(1, "not a fun that takes three arguments"),
                   fn ->
                     :maps.fold(:abc, 10, %{})
                   end
    end

    test "raises ArgumentError if the first argument is an anonymous function with arity different than 3" do
      assert_raise ArgumentError,
                   build_errors_found_msg(1, "not a fun that takes three arguments"),
                   fn ->
                     :maps.fold(fn -> :abc end, 10, %{})
                   end
    end

    test "raises BadMapError if the third argument is not a map", %{fun: fun} do
      assert_raise BadMapError, "expected a map, got: :abc", fn ->
        :maps.fold(fun, 10, :abc)
      end
    end
  end

  describe "from_list/1" do
    test "builds a map from the given list of key-value tuples" do
      assert :maps.from_list([{:a, 2}, {3, 4.0}]) == %{:a => 2, 3 => 4.0}
    end

    test "if the same key appears more than once, the latter (right-most) value is used and the previous values are ignored" do
      list = [
        {:a, 1},
        {:b, 2},
        {:a, 3},
        {:b, 4},
        {:a, 5},
        {:b, 6}
      ]

      assert :maps.from_list(list) == %{a: 5, b: 6}
    end

    test "raises ArgumentError if the argument is not a list" do
      assert_raise ArgumentError,
                   build_errors_found_msg(1, "not a list"),
                   fn ->
                     :maps.from_list(123)
                   end
    end
  end

  describe "get/2" do
    test "returns the value assiociated with the given key if map contains the key" do
      assert :maps.get(:b, %{a: 1, b: 2}) == 2
    end

    test "raises BadMapError if the second argument is not a map" do
      assert_raise BadMapError, "expected a map, got: 1", fn ->
        :maps.get(:a, build_value(1))
      end
    end

    test "raises KeyError if the map doesn't contain the given key" do
      assert_raise KeyError, "key :a not found in: %{}", fn ->
        :a
        |> build_value()
        |> :maps.get(%{})
      end
    end
  end

  describe "get/3" do
    test "returns the value assiociated with the given key if map contains the key" do
      assert :maps.get(:b, %{a: 1, b: 2}, :default_value) == 2
    end

    test "raises BadMapError if the second argument is not a map" do
      assert_raise BadMapError, "expected a map, got: 1", fn ->
        :maps.get(:a, 1, :default_value)
      end
    end

    test "returns the default value if the map doesn't contain the given key" do
      assert :maps.get(:a, %{}, :default_value) == :default_value
    end
  end

  describe "is_key/2" do
    test "returns true if the given map has the given key" do
      assert :maps.is_key(:b, %{a: 1, b: 2}) == true
    end

    test "returns false if the given map doesn't have the given key" do
      assert :maps.is_key(:c, %{a: 1, b: 2}) == false
    end

    test "raises BadMapError if the second argument is not a map" do
      assert_raise BadMapError, "expected a map, got: :abc", fn ->
        :x
        |> build_value()
        |> :maps.is_key(:abc)
      end
    end
  end

  describe "keys/1" do
    test "empty map" do
      assert :maps.keys(%{}) == []
    end

    test "non-empty map" do
      assert :maps.keys(%{a: 1, b: 2}) == [:a, :b]
    end

    test "not a map" do
      assert_raise BadMapError, "expected a map, got: :abc", fn ->
        :maps.keys(:abc)
      end
    end
  end

  describe "map/2" do
    setup do
      [fun: fn _key, value -> value * 10 end]
    end

    test "maps empty map", %{fun: fun} do
      assert :maps.map(fun, %{}) == %{}
    end

    test "maps non-empty map", %{fun: fun} do
      assert :maps.map(fun, %{a: 1, b: 2, c: 3}) == %{a: 10, b: 20, c: 30}
    end

    test "raises ArgumentError if the first argument is not an anonymous function" do
      assert_raise ArgumentError,
                   build_errors_found_msg(1, "not a fun that takes two arguments"),
                   fn ->
                     :maps.map(:abc, %{})
                   end
    end

    test "raises ArgumentError if the first argument is an anonymous function with arity different than 2" do
      assert_raise ArgumentError,
                   build_errors_found_msg(1, "not a fun that takes two arguments"),
                   fn ->
                     :maps.map(fn x -> x end, %{})
                   end
    end

    test "raises BadMapError if the second argument is not a map", %{fun: fun} do
      assert_raise BadMapError, "expected a map, got: :abc", fn ->
        :maps.map(fun, :abc)
      end
    end
  end

  describe "merge/2" do
    test "merges two maps" do
      map_1 = %{a: 1, b: 2}
      map_2 = %{c: 3, d: 4}

      assert :maps.merge(map_1, map_2) == %{a: 1, b: 2, c: 3, d: 4}
    end

    test "if two keys exist in both maps, the value in the first map is superseded by the value in the second map" do
      map_1 = %{a: 1, b: 2, c: 3}
      map_2 = %{c: 4, d: 5, a: 6}

      assert :maps.merge(map_1, map_2) == %{a: 6, b: 2, c: 4, d: 5}
    end

    test "raises BadMapError if the first argument is not a map" do
      assert_raise BadMapError, "expected a map, got: 123", fn ->
        123
        |> build_value()
        |> :maps.merge(%{a: 1})
      end
    end

    test "raises BadMapError if the second argument is not a map" do
      assert_raise BadMapError, "expected a map, got: 123", fn ->
        :maps.merge(%{a: 1}, 123)
      end
    end
  end

  describe "put/3" do
    test "when the map doesn't have the given key" do
      assert :maps.put(:b, 2, %{a: 1}) == %{a: 1, b: 2}
    end

    test "when the map already has the given key" do
      assert :maps.put(:b, 3, %{a: 1, b: 2}) == %{a: 1, b: 3}
    end

    test "raises BadMapError if the third argument is not a map" do
      assert_raise BadMapError, "expected a map, got: :abc", fn ->
        :maps.put(:a, 1, build_value(:abc))
      end
    end
  end

  describe "remove/2" do
    test "when the map has the given key" do
      assert :maps.remove(:b, %{a: 1, b: 2, c: 3}) == %{a: 1, c: 3}
    end

    test "when the map doesn't have the given key" do
      assert :maps.remove(:b, %{a: 1, c: 3}) == %{a: 1, c: 3}
    end

    test "raises BadMapError if the second argument is not a map" do
      assert_raise BadMapError, "expected a map, got: 123", fn ->
        :maps.remove(:b, 123)
      end
    end
  end

  describe "to_list/1" do
    test "returns an empty list if given an empty map" do
      assert :maps.to_list(%{}) == []
    end

    test "returns a list of tuples containing key-value pairs if given a non-empty map" do
      assert :maps.to_list(%{a: 1, b: 2}) == [{:a, 1}, {:b, 2}]
    end

    test "raises BadMapError if the argument is not a map" do
      assert_raise BadMapError, "expected a map, got: :abc", fn ->
        :maps.to_list(:abc)
      end
    end
  end
end
