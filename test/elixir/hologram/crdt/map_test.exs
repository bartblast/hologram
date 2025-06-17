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

  describe "CRDT properties" do
    test "idempotency: applying same operation multiple times has same effect" do
      # Test with put operation
      crdt_1 = CRDTMap.new()
      crdt_2 = CRDTMap.put(crdt_1, :key, "value", @timestamp_1)
      crdt_3 = CRDTMap.put(crdt_2, :key, "value", @timestamp_1)
      assert crdt_2 == crdt_3

      # Test with deletion operation
      crdt_4 = CRDTMap.delete(crdt_3, :key, @timestamp_2)
      crdt_5 = CRDTMap.delete(crdt_4, :key, @timestamp_2)
      assert crdt_4 == crdt_5

      # Test with conflicting operations (older timestamp should be ignored)
      crdt_6 = CRDTMap.put(crdt_5, :key, "old_value", @timestamp_1)
      crdt_7 = CRDTMap.put(crdt_6, :key, "old_value", @timestamp_1)
      assert crdt_6 == crdt_7
      # Should still be deleted
      assert CRDTMap.get(crdt_7, :key) == nil
    end

    test "commutativity: order of merge doesn't matter with conflicts" do
      # Test with overlapping keys and conflicting timestamps

      crdt_1 =
        CRDTMap.new()
        |> CRDTMap.put(:key_1, "value_1a", @timestamp_1)
        |> CRDTMap.put(:key_2, "value_2a", @timestamp_3)
        |> CRDTMap.delete(:key_3, @timestamp_2)

      crdt_2 =
        CRDTMap.new()
        |> CRDTMap.put(:key_1, "value_1b", @timestamp_2)
        |> CRDTMap.put(:key_2, "value_2b", @timestamp_1)
        |> CRDTMap.put(:key_3, "value_3", @timestamp_4)
        |> CRDTMap.put(:key_4, "value_4", @timestamp_1)

      merged_1_2 = CRDTMap.merge(crdt_1, crdt_2)
      merged_2_1 = CRDTMap.merge(crdt_2, crdt_1)

      # Should have identical internal structure regardless of merge order
      assert merged_1_2 == merged_2_1

      # Verify specific conflict resolutions
      # timestamp_2 > timestamp_1
      assert CRDTMap.get(merged_1_2, :key_1) == "value_1b"
      # timestamp_3 > timestamp_1
      assert CRDTMap.get(merged_1_2, :key_2) == "value_2a"
      # timestamp_4 > timestamp_2 (delete)
      assert CRDTMap.get(merged_1_2, :key_3) == "value_3"
      # only in crdt_2
      assert CRDTMap.get(merged_1_2, :key_4) == "value_4"
    end

    test "associativity: grouping of merges doesn't matter with complex conflicts" do
      # Create CRDTs with overlapping keys and various timestamps

      crdt_1 =
        CRDTMap.new()
        |> CRDTMap.put(:key_1, "value_1a", @timestamp_1)
        |> CRDTMap.put(:key_2, "value_2a", @timestamp_3)
        |> CRDTMap.delete(:key_4, @timestamp_1)

      crdt_2 =
        CRDTMap.new()
        |> CRDTMap.put(:key_1, "value_1b", @timestamp_2)
        |> CRDTMap.put(:key_3, "value_3a", @timestamp_2)
        |> CRDTMap.put(:key_4, "value_4a", @timestamp_3)

      crdt_3 =
        CRDTMap.new()
        |> CRDTMap.put(:key_2, "value_2b", @timestamp_1)
        |> CRDTMap.put(:key_3, "value_3b", @timestamp_4)
        |> CRDTMap.delete(:key_4, @timestamp_4)

      # Test (crdt_1 ∪ crdt_2) ∪ crdt_3
      merged_left =
        crdt_1
        |> CRDTMap.merge(crdt_2)
        |> CRDTMap.merge(crdt_3)

      # Test crdt_1 ∪ (crdt_2 ∪ crdt_3)
      merged_right = CRDTMap.merge(crdt_1, CRDTMap.merge(crdt_2, crdt_3))

      assert merged_left == merged_right

      # Verify final conflict resolutions
      # timestamp_2 wins
      assert CRDTMap.get(merged_left, :key_1) == "value_1b"
      # timestamp_3 wins
      assert CRDTMap.get(merged_left, :key_2) == "value_2a"
      # timestamp_4 wins
      assert CRDTMap.get(merged_left, :key_3) == "value_3b"
      # deleted at timestamp_4
      assert CRDTMap.get(merged_left, :key_4) == nil
    end

    test "convergence: concurrent operations eventually converge" do
      # Simulate concurrent operations on the same keys from different replicas
      base_crdt = CRDTMap.put(CRDTMap.new(), :shared, "initial", @timestamp_1)

      # Replica A operations
      replica_a =
        base_crdt
        |> CRDTMap.put(:shared, "from_a", @timestamp_3)
        |> CRDTMap.put(:a_only, "a_value", @timestamp_2)
        |> CRDTMap.delete(:to_delete, @timestamp_2)

      # Replica B operations (simulating concurrent updates)
      replica_b =
        base_crdt
        # Older timestamp
        |> CRDTMap.put(:shared, "from_b", @timestamp_2)
        |> CRDTMap.put(:b_only, "b_value", @timestamp_3)
        |> CRDTMap.put(:to_delete, "will_be_deleted", @timestamp_1)

      # Both replicas should converge to the same state regardless of merge order
      converged_ab = CRDTMap.merge(replica_a, replica_b)
      converged_ba = CRDTMap.merge(replica_b, replica_a)

      assert converged_ab == converged_ba

      # Verify LWW semantics
      # timestamp_3 > timestamp_2
      assert CRDTMap.get(converged_ab, :shared) == "from_a"
      assert CRDTMap.get(converged_ab, :a_only) == "a_value"
      assert CRDTMap.get(converged_ab, :b_only) == "b_value"
      # Delete wins over put
      assert CRDTMap.get(converged_ab, :to_delete) == nil
    end

    test "monotonicity: merge never loses information from newer timestamps" do
      crdt_old =
        CRDTMap.new()
        |> CRDTMap.put(:key_1, "old", @timestamp_1)
        |> CRDTMap.put(:key_2, "keep", @timestamp_3)

      crdt_new =
        CRDTMap.new()
        |> CRDTMap.put(:key_1, "new", @timestamp_2)
        # Older than existing put
        |> CRDTMap.delete(:key_2, @timestamp_1)
        |> CRDTMap.put(:key_3, "added", @timestamp_2)

      merged = CRDTMap.merge(crdt_old, crdt_new)

      # Should preserve the newest information for each key
      # timestamp_2 > timestamp_1
      assert CRDTMap.get(merged, :key_1) == "new"
      # timestamp_3 > timestamp_1 (delete ignored)
      assert CRDTMap.get(merged, :key_2) == "keep"
      # new key added
      assert CRDTMap.get(merged, :key_3) == "added"
    end

    test "delta and apply_delta round trip with complex operations" do
      # Start with a CRDT that has some data and deletions
      crdt_1 =
        CRDTMap.new()
        |> CRDTMap.put(:key_1, "old_value_1", @timestamp_1)
        |> CRDTMap.put(:key_2, "value_2", @timestamp_1)
        |> CRDTMap.delete(:key_3, @timestamp_1)

      # Create target CRDT with various operations including resurrections
      crdt_2 =
        CRDTMap.new()
        # Update existing
        |> CRDTMap.put(:key_1, "new_value_1", @timestamp_3)
        # Delete existing
        |> CRDTMap.delete(:key_2, @timestamp_2)
        # Resurrect deleted
        |> CRDTMap.put(:key_3, "resurrected", @timestamp_2)
        # New key
        |> CRDTMap.put(:key_4, "new_value_4", @timestamp_1)

      delta_ops = CRDTMap.delta(crdt_1, crdt_2)
      result = CRDTMap.apply_delta(crdt_1, delta_ops)

      assert result == crdt_2

      # Verify specific outcomes
      assert CRDTMap.get(result, :key_1) == "new_value_1"
      assert CRDTMap.get(result, :key_2) == nil
      assert CRDTMap.get(result, :key_3) == "resurrected"
      assert CRDTMap.get(result, :key_4) == "new_value_4"
    end
  end
end
