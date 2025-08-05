defmodule Hologram.Commons.MapUtilsTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Commons.MapUtils

  alias Hologram.Test.Fixtures.Commons.MapUtils.Module1
  alias Hologram.Test.Fixtures.Commons.MapUtils.Module2

  describe "diff/2" do
    test "both maps are empty" do
      result = diff(%{}, %{})

      assert result == %{
               added: [],
               removed: [],
               edited: []
             }
    end

    test "empty map to non-empty map" do
      result = diff(%{}, %{new: "value"})

      assert result == %{
               added: [{:new, "value"}],
               removed: [],
               edited: []
             }
    end

    test "non-empty map to empty map" do
      result = diff(%{"old" => "value"}, %{})

      assert result == %{
               added: [],
               removed: ["old"],
               edited: []
             }
    end

    test "map with edited values" do
      result = diff(%{key: "old"}, %{key: "new"})

      assert result == %{
               added: [],
               removed: [],
               edited: [{:key, "new"}]
             }
    end

    test "identical maps" do
      result = diff(%{"same" => "value"}, %{"same" => "value"})

      assert result == %{
               added: [],
               removed: [],
               edited: []
             }
    end

    test "complex case with added, removed, and edited entries" do
      result = diff(%{:abc => 1, 2 => "two"}, %{:abc => 10, 3 => "three"})

      assert result == %{
               added: [{3, "three"}],
               removed: [2],
               edited: [{:abc, 10}]
             }
    end

    test "nested maps with same content are equal" do
      nested_map = %{nested: "value"}
      old_map = %{data: nested_map}
      new_map = %{data: %{nested: "value"}}

      result = diff(old_map, new_map)

      assert result == %{
               added: [],
               removed: [],
               edited: []
             }
    end

    test "nil to not nil" do
      result = diff(%{key: nil}, %{key: "value"})

      assert result == %{
               added: [],
               removed: [],
               edited: [{:key, "value"}]
             }
    end

    test "nil to nil" do
      result = diff(%{key: nil}, %{key: nil})

      assert result == %{
               added: [],
               removed: [],
               edited: []
             }
    end

    test "strict equality is used for value comparison" do
      result = diff(%{number: 1}, %{number: 1.0})

      assert result == %{
               added: [],
               removed: [],
               edited: [{:number, 1.0}]
             }
    end

    test "large number of changes" do
      old_map = Enum.into(1..50, %{}, fn x -> {x, "old_#{x}"} end)
      new_map = Enum.into(26..75, %{}, fn x -> {x, "new_#{x}"} end)

      result = diff(old_map, new_map)

      # Keys 1-25 should be removed
      assert length(result.removed) == 25
      assert Enum.all?(result.removed, fn key -> key in 1..25 end)

      # Keys 26-50 should be edited
      assert length(result.edited) == 25
      assert Enum.all?(result.edited, fn {key, _value} -> key in 26..50 end)

      # Keys 51-75 should be added
      assert length(result.added) == 25
      assert Enum.all?(result.added, fn {key, _value} -> key in 51..75 end)
    end
  end

  describe "put_nested/3" do
    test "single level, new key" do
      data = %{a: 1}
      result = put_nested(data, [:b], 2)

      assert result == %{a: 1, b: 2}
    end

    test "single level, existing key" do
      data = %{a: 1, b: 2}
      result = put_nested(data, [:b], 3)

      assert result == %{a: 1, b: 3}
    end

    test "two levels, new key" do
      data = %{a: 1, b: %{c: 2}}
      result = put_nested(data, [:b, :d], 3)

      assert result == %{a: 1, b: %{c: 2, d: 3}}
    end

    test "two levels, existing key" do
      data = %{a: 1, b: %{c: 2, d: 3}}
      result = put_nested(data, [:b, :d], 4)

      assert result == %{a: 1, b: %{c: 2, d: 4}}
    end

    test "three levels, new key" do
      data = %{a: 1, b: %{c: 2, d: %{e: 3}}}
      result = put_nested(data, [:b, :d, :f], 4)

      assert result == %{a: 1, b: %{c: 2, d: %{e: 3, f: 4}}}
    end

    test "three levels, existing key" do
      data = %{a: 1, b: %{c: 2, d: %{e: 3, f: 4}}}
      result = put_nested(data, [:b, :d, :f], 5)

      assert result == %{a: 1, b: %{c: 2, d: %{e: 3, f: 5}}}
    end

    test "works with structs" do
      data = %Module1{x: 1, y: %Module2{m: 1, n: 2}}
      result = put_nested(data, [:y, :n], 3)

      assert result == %Module1{x: 1, y: %Module2{m: 1, n: 3}}
    end

    test "mixed map and struct deep nesting" do
      data = %{
        a: 1,
        b: %Module1{
          x: 2,
          y: %{
            c: 3,
            d: %Module2{
              m: 4,
              n: %{
                e: 5,
                f: 6
              }
            }
          }
        }
      }

      result = put_nested(data, [:b, :y, :d, :n, :f], 99)

      assert result == %{
               a: 1,
               b: %Module1{
                 x: 2,
                 y: %{
                   c: 3,
                   d: %Module2{
                     m: 4,
                     n: %{
                       e: 5,
                       f: 99
                     }
                   }
                 }
               }
             }
    end
  end
end
