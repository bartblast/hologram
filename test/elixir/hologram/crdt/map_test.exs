defmodule Hologram.CRDT.MapTest do
  use Hologram.Test.BasicCase, async: true

  alias Hologram.CRDT.Map, as: CRDTMap

  @timestamp_1 1_000
  @timestamp_2 2_000
  @timestamp_3 3_000
  @timestamp_4 4_000

  describe "apply_delta/2" do
    test "applies empty delta list" do
      crdt = CRDTMap.put(CRDTMap.new(), :key, "value", @timestamp_1)

      result = CRDTMap.apply_delta(crdt, [])

      assert result == crdt
    end

    test "applies put operations" do
      crdt = CRDTMap.new()

      operations = [
        {:put, :key_1, "value_1", @timestamp_1},
        {:put, :key_2, "value_2", @timestamp_1}
      ]

      result = CRDTMap.apply_delta(crdt, operations)

      assert CRDTMap.get(result, :key_1) == "value_1"
      assert CRDTMap.get(result, :key_2) == "value_2"
    end

    test "applies delete operations" do
      crdt =
        CRDTMap.new()
        |> CRDTMap.put(:key_1, "value_1", @timestamp_1)
        |> CRDTMap.put(:key_2, "value_2", @timestamp_1)

      operations = [{:delete, :key_1, @timestamp_2}, {:delete, :key_2, @timestamp_2}]

      result = CRDTMap.apply_delta(crdt, operations)

      assert CRDTMap.get(result, :key_1) == nil
      assert CRDTMap.get(result, :key_2) == nil
    end

    test "applies mixed operations based on timestamps, not order" do
      crdt = CRDTMap.new()

      # Operations are intentionally out of timestamp order to test LWW behavior
      operations = [
        {:put, :key, "value_2", @timestamp_3},
        {:delete, :key, @timestamp_2},
        {:put, :key, "value_3", @timestamp_4},
        {:put, :key, "value_1", @timestamp_1}
      ]

      result = CRDTMap.apply_delta(crdt, operations)

      # Should get "value_3" because it has the highest timestamp (@timestamp_4)
      assert CRDTMap.get(result, :key) == "value_3"
    end
  end

  describe "delete/3" do
    test "creates correct tombstone structure for non-existent key" do
      result = CRDTMap.delete(CRDTMap.new(), :key, @timestamp_1)

      # Note: no value field for tombstones
      assert result.entries[:key] == %{
               timestamp: @timestamp_1,
               deleted: true
             }
    end

    test "creates correct tombstone structure when deleting existing entry" do
      initial_crdt = CRDTMap.put(CRDTMap.new(), :key, "value", @timestamp_1)
      result = CRDTMap.delete(initial_crdt, :key, @timestamp_2)

      # Note: no value field for tombstones
      assert result.entries[:key] == %{
               timestamp: @timestamp_2,
               deleted: true
             }
    end

    test "ignores delete when older timestamp" do
      initial_crdt = CRDTMap.put(CRDTMap.new(), :key, "value", @timestamp_2)
      result = CRDTMap.delete(initial_crdt, :key, @timestamp_1)

      assert CRDTMap.get(result, :key) == "value"
      assert result.entries[:key].deleted == false
    end

    test "uses current timestamp when none provided" do
      initial_crdt = CRDTMap.put(CRDTMap.new(), :key, "value", @timestamp_1)
      result = CRDTMap.delete(initial_crdt, :key)

      assert CRDTMap.get(result, :key) == nil
      assert result.entries[:key].deleted == true
      assert result.entries[:key].timestamp > @timestamp_1
    end
  end

  describe "delta/2" do
    test "returns empty list for identical CRDTs" do
      crdt_1 = CRDTMap.put(CRDTMap.new(), :key, "value", @timestamp_1)
      crdt_2 = CRDTMap.put(CRDTMap.new(), :key, "value", @timestamp_1)

      result = CRDTMap.delta(crdt_1, crdt_2)

      assert result == []
    end

    test "returns put operation for new key in target" do
      crdt_1 = CRDTMap.new()
      crdt_2 = CRDTMap.put(CRDTMap.new(), :key, "value", @timestamp_1)

      result = CRDTMap.delta(crdt_1, crdt_2)

      assert result == [{:put, :key, "value", @timestamp_1}]
    end

    test "returns delete operation for deleted key in target" do
      crdt_1 = CRDTMap.new()
      crdt_2 = CRDTMap.delete(CRDTMap.new(), :key, @timestamp_1)

      result = CRDTMap.delta(crdt_1, crdt_2)

      assert result == [{:delete, :key, @timestamp_1}]
    end

    test "returns put operation for newer value in target" do
      crdt_1 = CRDTMap.put(CRDTMap.new(), :key, "value_1", @timestamp_1)
      crdt_2 = CRDTMap.put(CRDTMap.new(), :key, "value_2", @timestamp_2)

      result = CRDTMap.delta(crdt_1, crdt_2)

      assert result == [{:put, :key, "value_2", @timestamp_2}]
    end

    test "returns no operation for older value in target" do
      crdt_1 = CRDTMap.put(CRDTMap.new(), :key, "value_1", @timestamp_2)
      crdt_2 = CRDTMap.put(CRDTMap.new(), :key, "value_2", @timestamp_1)

      result = CRDTMap.delta(crdt_1, crdt_2)

      assert result == []
    end

    test "returns multiple operations for complex differences" do
      crdt_1 =
        CRDTMap.new()
        |> CRDTMap.put(:key_1, "value_1", @timestamp_1)
        |> CRDTMap.put(:key_2, "value_2", @timestamp_1)

      crdt_2 =
        CRDTMap.new()
        |> CRDTMap.put(:key_1, "new_value", @timestamp_2)
        |> CRDTMap.delete(:key_2, @timestamp_2)
        |> CRDTMap.put(:key_3, "value_3", @timestamp_1)

      result = CRDTMap.delta(crdt_1, crdt_2)

      expected = [
        {:put, :key_1, "new_value", @timestamp_2},
        {:delete, :key_2, @timestamp_2},
        {:put, :key_3, "value_3", @timestamp_1}
      ]

      assert Enum.sort(result) == Enum.sort(expected)
    end
  end

  describe "empty?/1" do
    test "returns true for new CRDT" do
      crdt = CRDTMap.new()

      assert CRDTMap.empty?(crdt)
    end

    test "returns false when CRDT has entries" do
      crdt = CRDTMap.put(CRDTMap.new(), :key, "value", @timestamp_1)

      refute CRDTMap.empty?(crdt)
    end

    test "returns true when all entries are deleted" do
      crdt =
        CRDTMap.new()
        |> CRDTMap.put(:key, "value", @timestamp_1)
        |> CRDTMap.delete(:key, @timestamp_2)

      assert CRDTMap.empty?(crdt)
    end
  end

  describe "get/2" do
    test "returns nil for non-existent key" do
      crdt = CRDTMap.new()

      assert CRDTMap.get(crdt, :non_existent) == nil
    end

    test "returns value for existing key" do
      crdt = CRDTMap.put(CRDTMap.new(), :key, "value", @timestamp_1)

      assert CRDTMap.get(crdt, :key) == "value"
    end

    test "returns nil for deleted key" do
      crdt =
        CRDTMap.new()
        |> CRDTMap.put(:key, "value", @timestamp_1)
        |> CRDTMap.delete(:key, @timestamp_2)

      assert CRDTMap.get(crdt, :key) == nil
    end
  end

  describe "merge/2" do
    test "merges two empty CRDTs" do
      crdt_1 = CRDTMap.new()
      crdt_2 = CRDTMap.new()

      result = CRDTMap.merge(crdt_1, crdt_2)

      assert CRDTMap.empty?(result)
    end

    test "merges CRDT with non-overlapping keys" do
      crdt_1 = CRDTMap.put(CRDTMap.new(), :key_1, "value_1", @timestamp_1)
      crdt_2 = CRDTMap.put(CRDTMap.new(), :key_2, "value_2", @timestamp_1)

      result = CRDTMap.merge(crdt_1, crdt_2)

      assert CRDTMap.size(result) == 2
      assert CRDTMap.get(result, :key_1) == "value_1"
      assert CRDTMap.get(result, :key_2) == "value_2"
    end

    test "merges CRDTs with newer timestamp winning" do
      crdt_1 = CRDTMap.put(CRDTMap.new(), :key, "value_1", @timestamp_1)
      crdt_2 = CRDTMap.put(CRDTMap.new(), :key, "value_2", @timestamp_2)

      result = CRDTMap.merge(crdt_1, crdt_2)

      assert CRDTMap.get(result, :key) == "value_2"
      assert result.entries[:key].timestamp == @timestamp_2
    end

    test "merges CRDTs with deletion winning over older put" do
      crdt_1 = CRDTMap.put(CRDTMap.new(), :key, "value", @timestamp_1)
      crdt_2 = CRDTMap.delete(CRDTMap.new(), :key, @timestamp_2)

      result = CRDTMap.merge(crdt_1, crdt_2)

      assert CRDTMap.get(result, :key) == nil
      assert result.entries[:key].deleted == true
    end

    test "merges CRDTs with put winning over older deletion" do
      crdt_1 = CRDTMap.delete(CRDTMap.new(), :key, @timestamp_1)
      crdt_2 = CRDTMap.put(CRDTMap.new(), :key, "value", @timestamp_2)

      result = CRDTMap.merge(crdt_1, crdt_2)

      assert CRDTMap.get(result, :key) == "value"
      assert result.entries[:key].deleted == false
    end
  end

  describe "new/0" do
    test "creates an empty CRDT map" do
      assert CRDTMap.new() == %CRDTMap{entries: %{}}
    end
  end

  describe "put/4" do
    test "creates correct entry structure for new key" do
      result = CRDTMap.put(CRDTMap.new(), :key, "value", @timestamp_1)

      assert result.entries[:key] == %{
               value: "value",
               timestamp: @timestamp_1,
               deleted: false
             }
    end

    test "adds a new entry with current timestamp when none provided" do
      result = CRDTMap.put(CRDTMap.new(), :key, "value")

      assert CRDTMap.get(result, :key) == "value"
      assert result.entries[:key].timestamp > 0
    end

    test "adds a new entry with provided timestamp" do
      result = CRDTMap.put(CRDTMap.new(), :key, "value", @timestamp_1)

      assert CRDTMap.get(result, :key) == "value"
      assert result.entries[:key].timestamp == @timestamp_1
    end

    test "creates correct entry structure when updating existing key" do
      result =
        CRDTMap.new()
        |> CRDTMap.put(:key, "old_value", @timestamp_1)
        |> CRDTMap.put(:key, "new_value", @timestamp_2)

      assert result.entries[:key] == %{
               value: "new_value",
               timestamp: @timestamp_2,
               deleted: false
             }
    end

    test "updates an existing entry when newer timestamp" do
      result =
        CRDTMap.new()
        |> CRDTMap.put(:key, "value_1", @timestamp_1)
        |> CRDTMap.put(:key, "value_2", @timestamp_2)

      assert CRDTMap.get(result, :key) == "value_2"
      assert result.entries[:key].timestamp == @timestamp_2
    end

    test "ignores update when older timestamp" do
      result =
        CRDTMap.new()
        |> CRDTMap.put(:key, "value_1", @timestamp_2)
        |> CRDTMap.put(:key, "value_2", @timestamp_1)

      assert CRDTMap.get(result, :key) == "value_1"
      assert result.entries[:key].timestamp == @timestamp_2
    end

    test "ignores update when same timestamp" do
      result =
        CRDTMap.new()
        |> CRDTMap.put(:key, "value_1", @timestamp_1)
        |> CRDTMap.put(:key, "value_2", @timestamp_1)

      assert CRDTMap.get(result, :key) == "value_1"
    end

    test "can resurrect deleted entry with newer timestamp" do
      result =
        CRDTMap.new()
        |> CRDTMap.put(:key, "value_1", @timestamp_1)
        |> CRDTMap.delete(:key, @timestamp_2)
        |> CRDTMap.put(:key, "value_2", @timestamp_3)

      assert CRDTMap.get(result, :key) == "value_2"
      assert result.entries[:key].timestamp == @timestamp_3
      assert result.entries[:key].deleted == false
    end
  end

  describe "size/1" do
    test "returns 0 for empty CRDT" do
      crdt = CRDTMap.new()

      assert CRDTMap.size(crdt) == 0
    end

    test "returns correct count for non-deleted entries" do
      crdt =
        CRDTMap.new()
        |> CRDTMap.put(:key_1, "value_1", @timestamp_1)
        |> CRDTMap.put(:key_2, "value_2", @timestamp_1)
        |> CRDTMap.put(:key_3, "value_3", @timestamp_1)

      assert CRDTMap.size(crdt) == 3
    end

    test "excludes deleted entries from count" do
      crdt =
        CRDTMap.new()
        |> CRDTMap.put(:key_1, "value_1", @timestamp_1)
        |> CRDTMap.put(:key_2, "value_2", @timestamp_1)
        |> CRDTMap.delete(:key_2, @timestamp_2)

      assert CRDTMap.size(crdt) == 1
    end
  end

  describe "to_map/1" do
    test "returns empty map for empty CRDT" do
      crdt = CRDTMap.new()

      assert CRDTMap.to_map(crdt) == %{}
    end

    test "returns map with non-deleted entries" do
      crdt =
        CRDTMap.new()
        |> CRDTMap.put(:key_1, "value_1", @timestamp_1)
        |> CRDTMap.put(:key_2, "value_2", @timestamp_1)

      result = CRDTMap.to_map(crdt)

      assert result == %{key_1: "value_1", key_2: "value_2"}
    end

    test "excludes deleted entries" do
      crdt =
        CRDTMap.new()
        |> CRDTMap.put(:key_1, "value_1", @timestamp_1)
        |> CRDTMap.put(:key_2, "value_2", @timestamp_1)
        |> CRDTMap.delete(:key_2, @timestamp_2)

      result = CRDTMap.to_map(crdt)

      assert result == %{key_1: "value_1"}
    end
  end
end
