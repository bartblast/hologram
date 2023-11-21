defmodule Hologram.ExJsConsistency.Erlang.MapsTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/maps_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

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

    test "returns false if the given map has the given key" do
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
end
