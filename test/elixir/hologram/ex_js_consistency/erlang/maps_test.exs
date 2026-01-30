defmodule Hologram.ExJsConsistency.Erlang.MapsTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/maps_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  describe "find/2" do
    @map %{"one" => 1, "two" => 2}

    test "key exists in map" do
      key = "two"
      assert :maps.find(key, @map) == {:ok, 2}
    end

    test "key does not exist in map" do
      key = "hello"
      assert :maps.find(key, @map) == :error
    end

    test "raises BadMapError if the second argument is not a map" do
      assert_error BadMapError, "expected a map, got: 1", {:maps, :find, ["a", 1]}
    end
  end

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
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a fun that takes three arguments"),
                   fn ->
                     :maps.fold(:abc, 10, %{})
                   end
    end

    test "raises ArgumentError if the first argument is an anonymous function with arity different than 3" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a fun that takes three arguments"),
                   fn ->
                     :maps.fold(fn -> :abc end, 10, %{})
                   end
    end

    test "raises BadMapError if the third argument is not a map", %{fun: fun} do
      assert_error BadMapError, "expected a map, got: :abc", fn ->
        :maps.fold(fun, 10, :abc)
      end
    end
  end

  describe "from_keys/2" do
    test "creates a map with multiple keys" do
      assert :maps.from_keys([:a, :b], 1) === %{a: 1, b: 1}
    end

    test "creates a map with a single key" do
      assert :maps.from_keys([:a], 1) === %{a: 1}
    end

    test "creates an empty map if the list of keys is empty" do
      assert :maps.from_keys([], 1) === %{}
    end

    test "raises ArgumentError if the first argument is not a list" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a list"),
                   {:maps, :from_keys, [:a, 1]}
    end

    test "raises ArgumentError if the first argument is not a proper list" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a proper list"),
                   {:maps, :from_keys, [[:a | :b], 1]}
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
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a list"),
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
      assert_error BadMapError, "expected a map, got: 1", {:maps, :get, [:a, 1]}
    end

    test "raises KeyError if the map doesn't contain the given key" do
      assert_error KeyError, build_key_error_msg(:a, %{}), {:maps, :get, [:a, %{}]}
    end
  end

  describe "get/3" do
    test "returns the value assiociated with the given key if map contains the key" do
      assert :maps.get(:b, %{a: 1, b: 2}, :default_value) == 2
    end

    test "raises BadMapError if the second argument is not a map" do
      assert_error BadMapError, "expected a map, got: 1", fn ->
        :maps.get(:a, 1, :default_value)
      end
    end

    test "returns the default value if the map doesn't contain the given key" do
      assert :maps.get(:a, %{}, :default_value) == :default_value
    end
  end

  describe "intersect/2" do
    test "takes value from map2" do
      assert :maps.intersect(%{a: 1, b: 3}, %{a: 2, c: 4}) == %{a: 2}
    end

    test "handles not strictly equal keys" do
      assert :maps.intersect(%{1 => 1}, %{1.0 => 2}) == %{}
    end

    test "returns an empty map when no common keys exist" do
      assert :maps.intersect(%{a: 1, b: 3}, %{c: 2, d: 4}) == %{}
    end

    test "returns an empty map when map1 is empty" do
      assert :maps.intersect(%{}, %{a: 2}) == %{}
    end

    test "returns an empty map when map2 is empty" do
      assert :maps.intersect(%{a: 1}, %{}) == %{}
    end

    test "returns an empty map when map1 and map2 are empty" do
      assert :maps.intersect(%{}, %{}) == %{}
    end

    test "doesn't mutate the inputs" do
      map1 = %{:a => 1, "a" => 3, 1 => 5, 1.0 => 7, {:a, :b} => 9}
      map2 = %{:a => 2, "a" => 4, 1 => 6, 1.0 => 8, {:a, :b} => 10}
      :maps.intersect(map1, map2)
      assert map1 == %{:a => 1, "a" => 3, 1 => 5, 1.0 => 7, {:a, :b} => 9}
      assert map2 == %{:a => 2, "a" => 4, 1 => 6, 1.0 => 8, {:a, :b} => 10}
    end

    test "raises when map1 is not a map" do
      assert_error BadMapError, "expected a map, got: :abc", fn ->
        :maps.intersect(:abc, %{})
      end
    end

    test "raises when map2 is not a map" do
      assert_error BadMapError, "expected a map, got: :abc", fn ->
        :maps.intersect(%{}, :abc)
      end
    end
  end

  describe "intersect_with/3" do
    setup do
      [combiner: fn _k, v1, v2 -> v1 + v2 end]
    end

    test "combines values with function", %{combiner: combiner} do
      map1 = %{a: 1, b: 3}
      map2 = %{a: 2, c: 4}

      assert :maps.intersect_with(combiner, map1, map2) == %{a: 3}
    end

    test "handles multiple common keys", %{combiner: combiner} do
      map1 = %{:a => 1, "a" => 2, 1 => 3}
      map2 = %{:a => 10, "a" => 20, 1 => 30}

      assert :maps.intersect_with(combiner, map1, map2) == %{:a => 11, "a" => 22, 1 => 33}
    end

    test "returns an empty map when no keys are common", %{combiner: combiner} do
      map1 = %{a: 1, b: 3}
      map2 = %{c: 2, d: 4}

      assert :maps.intersect_with(combiner, map1, map2) == %{}
    end

    test "returns an empty map when map1 is empty", %{combiner: combiner} do
      assert :maps.intersect_with(combiner, %{}, %{a: 2}) == %{}
    end

    test "returns an empty map when map2 is empty", %{combiner: combiner} do
      assert :maps.intersect_with(combiner, %{a: 1}, %{}) == %{}
    end

    test "returns an empty map when both maps are empty", %{combiner: combiner} do
      assert :maps.intersect_with(combiner, %{}, %{}) == %{}
    end

    test "raises ArgumentError if the first argument is not an anonymous function" do
      assert_error ArgumentError,
                   "errors were found at the given arguments:\n\n  * 1st argument: not a fun that takes three arguments\n",
                   fn -> :maps.intersect_with(:abc, %{}, %{}) end
    end

    test "raises ArgumentError if the first argument is an anonymous function with arity different than 3" do
      assert_error ArgumentError,
                   "errors were found at the given arguments:\n\n  * 1st argument: not a fun that takes three arguments\n",
                   fn -> :maps.intersect_with(fn v1, v2 -> v1 + v2 end, %{}, %{}) end
    end

    test "raises BadMapError if the second argument is not a map", %{combiner: combiner} do
      assert_error BadMapError, "expected a map, got: :abc", fn ->
        :maps.intersect_with(combiner, :abc, %{})
      end
    end

    test "raises BadMapError if the third argument is not a map", %{combiner: combiner} do
      assert_error BadMapError, "expected a map, got: :abc", fn ->
        :maps.intersect_with(combiner, %{}, :abc)
      end
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
      assert_error BadMapError, "expected a map, got: :abc", {:maps, :is_key, [:x, :abc]}
    end
  end

  describe "iterator/1" do
    test "empty map" do
      assert :maps.iterator(%{}) == [0 | %{}]
    end

    test "non-empty map" do
      assert :maps.iterator(%{a: 1, b: 2}) == [0 | %{a: 1, b: 2}]
    end

    test "not a map" do
      assert_error BadMapError, "expected a map, got: :abc", fn ->
        :maps.iterator(:abc)
      end
    end
  end

  describe "keys/1" do
    test "empty map" do
      assert :maps.keys(%{}) == []
    end

    test "non-empty map" do
      sorted_result =
        %{a: 1, b: 2}
        |> :maps.keys()
        |> Enum.sort()

      assert sorted_result == [:a, :b]
    end

    test "not a map" do
      assert_error BadMapError, "expected a map, got: :abc", fn ->
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
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a fun that takes two arguments"),
                   fn ->
                     :maps.map(:abc, %{})
                   end
    end

    test "raises ArgumentError if the first argument is an anonymous function with arity different than 2" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a fun that takes two arguments"),
                   fn ->
                     :maps.map(fn x -> x end, %{})
                   end
    end

    test "raises BadMapError if the second argument is not a map", %{fun: fun} do
      assert_error BadMapError, "expected a map, got: :abc", fn ->
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
      assert_error BadMapError, "expected a map, got: 123", {:maps, :merge, [123, %{a: 1}]}
    end

    test "raises BadMapError if the second argument is not a map" do
      assert_error BadMapError, "expected a map, got: 123", fn ->
        :maps.merge(%{a: 1}, 123)
      end
    end
  end

  describe "merge_with/3" do
    setup do
      [combiner: fn _k, v1, v2 -> v1 + v2 end]
    end

    test "combines overlapping keys with combiner", %{combiner: combiner} do
      map_1 = %{a: 1, b: 2}
      map_2 = %{b: 3, c: 4}

      assert :maps.merge_with(combiner, map_1, map_2) == %{a: 1, b: 5, c: 4}
    end

    test "when all keys overlap", %{combiner: combiner} do
      map_1 = %{a: 1, b: 2}
      map_2 = %{a: 10, b: 20}

      assert :maps.merge_with(combiner, map_1, map_2) == %{a: 11, b: 22}
    end

    test "when no keys overlap", %{combiner: combiner} do
      map_1 = %{a: 1}
      map_2 = %{b: 2}

      assert :maps.merge_with(combiner, map_1, map_2) == %{a: 1, b: 2}
    end

    test "when first map is empty", %{combiner: combiner} do
      map_1 = %{}
      map_2 = %{a: 1, b: 2}

      assert :maps.merge_with(combiner, map_1, map_2) == %{a: 1, b: 2}
    end

    test "when second map is empty", %{combiner: combiner} do
      map_1 = %{a: 1, b: 2}
      map_2 = %{}

      assert :maps.merge_with(combiner, map_1, map_2) == %{a: 1, b: 2}
    end

    test "when both maps are empty", %{combiner: combiner} do
      assert :maps.merge_with(combiner, %{}, %{}) == %{}
    end

    test "doesn't mutate its arguments", %{combiner: combiner} do
      map_1 = %{a: 1, b: 2}
      map_1_copy = Map.new(map_1)

      map_2 = %{b: 3, c: 4}
      map_2_copy = Map.new(map_2)

      _result = :maps.merge_with(combiner, map_1, map_2)

      assert map_1 == map_1_copy
      assert map_2 == map_2_copy
    end

    test "raises ArgumentError if the first argument is not an anonymous function" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a fun that takes three arguments"),
                   fn ->
                     :maps.merge_with(:not_a_function, %{a: 1}, %{b: 2})
                   end
    end

    test "raises ArgumentError if the first argument is an anonymous function with arity different than 3" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a fun that takes three arguments"),
                   fn ->
                     :maps.merge_with(fn x, y -> x + y end, %{a: 1}, %{b: 2})
                   end
    end

    test "raises BadMapError if the second argument is not a map", %{combiner: combiner} do
      assert_error BadMapError, "expected a map, got: 123", fn ->
        :maps.merge_with(combiner, 123, %{a: 1})
      end
    end

    test "raises BadMapError if the third argument is not a map", %{combiner: combiner} do
      assert_error BadMapError, "expected a map, got: 123", fn ->
        :maps.merge_with(combiner, %{a: 1}, 123)
      end
    end
  end

  describe "next/1" do
    test "initial iterator with empty map" do
      result =
        %{}
        |> :maps.iterator()
        |> :maps.next()

      assert result == :none
    end

    test "initial iterator with non-empty map" do
      result =
        %{a: 1, b: 2, c: 3}
        |> :maps.iterator()
        |> :maps.next()

      expected_1 = {:a, 1, {:b, 2, {:c, 3, :none}}}
      expected_2 = {:a, 1, {:c, 3, {:b, 2, :none}}}
      expected_3 = {:b, 2, {:a, 1, {:c, 3, :none}}}
      expected_4 = {:b, 2, {:c, 3, {:a, 1, :none}}}
      expected_5 = {:c, 3, {:a, 1, {:b, 2, :none}}}
      expected_6 = {:c, 3, {:b, 2, {:a, 1, :none}}}

      # Maps in Erlang/Elixir do not guarantee a specific order for key-value pairs.
      # The :maps.next/1 function returns a tuple {Key, Value, Iterator}, where Iterator
      # represents the remaining key-value pairs in an unspecified order.
      # This test accounts for all possible orderings of the map's key-value pairs.
      assert result in [expected_1, expected_2, expected_3, expected_4, expected_5, expected_6]
    end

    test "non-initial empty iterator" do
      result =
        %{}
        |> :maps.iterator()
        |> :maps.next()
        |> :maps.next()

      assert result == :none
    end

    test "non-initial non-empty iterator" do
      iter =
        %{a: 1, b: 2, c: 3}
        |> :maps.iterator()
        |> :maps.next()

      assert :maps.next(iter) == iter
    end

    test "not an iterator" do
      assert_error ArgumentError, build_argument_error_msg(1, "not a valid iterator"), fn ->
        :maps.next(123)
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
      assert_error BadMapError, "expected a map, got: :abc", {:maps, :put, [:a, 1, :abc]}
    end

    test "doesn't mutate the original map" do
      map = %{a: 1, b: 2}
      :maps.put(:c, 3, map)
      assert map == %{a: 1, b: 2}
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
      assert_error BadMapError, "expected a map, got: 123", fn ->
        :maps.remove(:b, 123)
      end
    end

    test "doesn't mutate the original map" do
      map = %{a: 1, b: 2}
      :maps.remove(:b, map)
      assert map == %{a: 1, b: 2}
    end
  end

  describe "take/2" do
    test "key exists in map" do
      map = %{a: 1, b: 2, c: 3}

      assert :maps.take(:b, map) == {2, %{a: 1, c: 3}}
    end

    test "key does not exist in map" do
      map = %{a: 1, c: 3}

      assert :maps.take(:b, map) == :error
    end

    test "empty map" do
      assert :maps.take(:a, %{}) == :error
    end

    test "key exists and value is nil" do
      assert :maps.take(:a, %{a: nil, b: 2}) == {nil, %{b: 2}}
    end

    test "doesn't mutate the original map" do
      map = %{a: 1, b: 2}
      :maps.take(:a, map)

      assert map == %{a: 1, b: 2}
    end

    test "raises BadMapError if the second argument is not a map" do
      assert_error BadMapError, "expected a map, got: 123", fn ->
        :maps.take(:a, 123)
      end
    end
  end

  describe "to_list/1" do
    test "returns an empty list if given an empty map" do
      assert :maps.to_list(%{}) == []
    end

    test "returns a list of tuples containing key-value pairs if given a non-empty map" do
      sorted_result =
        %{a: 1, b: 2}
        |> :maps.to_list()
        |> Enum.sort()

      assert sorted_result == [{:a, 1}, {:b, 2}]
    end

    test "raises BadMapError if the argument is not a map" do
      assert_error BadMapError, "expected a map, got: :abc", fn ->
        :maps.to_list(:abc)
      end
    end
  end

  describe "update/3" do
    test "when the map doesn't have the given key" do
      assert_error KeyError, build_key_error_msg(:b, %{a: 1}), fn ->
        :maps.update(:b, 2, %{a: 1})
      end
    end

    test "when the map already has the given key" do
      assert :maps.update(:b, 3, %{a: 1, b: 2}) == %{a: 1, b: 3}
    end

    test "raises BadMapError if the third argument is not a map" do
      assert_error BadMapError, "expected a map, got: :abc", fn ->
        :maps.update(:a, 1, :abc)
      end
    end
  end

  describe "values/1" do
    test "empty map" do
      assert :maps.values(%{}) == []
    end

    test "non-empty map" do
      sorted_result =
        %{a: 1, b: 2}
        |> :maps.values()
        |> Enum.sort()

      assert sorted_result == [1, 2]
    end

    test "not a map" do
      assert_error BadMapError, "expected a map, got: :abc", fn ->
        :maps.values(:abc)
      end
    end
  end
end
