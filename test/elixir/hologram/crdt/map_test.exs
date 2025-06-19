defmodule Hologram.CRDT.MapTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.CRDT.Map

  @timestamp_1 1_000
  @timestamp_2 2_000
  @timestamp_3 3_000
  @timestamp_4 4_000

  describe "apply_delta/2" do
    test "applies empty delta list" do
      crdt = put(new(), :key, "value", @timestamp_1)

      result = apply_delta(crdt, [])

      assert result == crdt
    end

    test "applies put operations" do
      crdt = new()

      operations = [
        {:put, :key_1, "value_1", @timestamp_1},
        {:put, :key_2, "value_2", @timestamp_1}
      ]

      result = apply_delta(crdt, operations)

      assert get(result, :key_1) == "value_1"
      assert get(result, :key_2) == "value_2"
    end

    test "applies delete operations" do
      crdt =
        new()
        |> put(:key_1, "value_1", @timestamp_1)
        |> put(:key_2, "value_2", @timestamp_1)

      operations = [{:delete, :key_1, @timestamp_2}, {:delete, :key_2, @timestamp_2}]

      result = apply_delta(crdt, operations)

      assert get(result, :key_1) == nil
      assert get(result, :key_2) == nil
    end

    test "applies mixed operations based on timestamps, not order" do
      crdt = new()

      # Operations are intentionally out of timestamp order to test LWW behavior
      operations = [
        {:put, :key, "value_2", @timestamp_3},
        {:delete, :key, @timestamp_2},
        {:put, :key, "value_3", @timestamp_4},
        {:put, :key, "value_1", @timestamp_1}
      ]

      result = apply_delta(crdt, operations)

      # Should get "value_3" because it has the highest timestamp (@timestamp_4)
      assert get(result, :key) == "value_3"
    end
  end

  describe "delete/3" do
    test "creates correct tombstone structure for non-existent key" do
      result = delete(new(), :key, @timestamp_1)

      # Note: no value field for tombstones
      assert result.entries[:key] == %{
               timestamp: @timestamp_1,
               deleted: true
             }
    end

    test "creates correct tombstone structure when deleting existing entry" do
      initial_crdt = put(new(), :key, "value", @timestamp_1)
      result = delete(initial_crdt, :key, @timestamp_2)

      # Note: no value field for tombstones
      assert result.entries[:key] == %{
               timestamp: @timestamp_2,
               deleted: true
             }
    end

    test "ignores delete when older timestamp" do
      initial_crdt = put(new(), :key, "value", @timestamp_2)
      result = delete(initial_crdt, :key, @timestamp_1)

      assert get(result, :key) == "value"
      assert result.entries[:key].deleted == false
    end

    test "uses current timestamp when none provided" do
      initial_crdt = put(new(), :key, "value", @timestamp_1)
      result = delete(initial_crdt, :key)

      assert get(result, :key) == nil
      assert result.entries[:key].deleted == true
      assert result.entries[:key].timestamp > @timestamp_1
    end
  end

  describe "delta/2" do
    test "returns empty list for identical CRDTs" do
      crdt_1 = put(new(), :key, "value", @timestamp_1)
      crdt_2 = put(new(), :key, "value", @timestamp_1)

      result = delta(crdt_1, crdt_2)

      assert result == []
    end

    test "returns put operation for new key in target" do
      crdt_1 = new()
      crdt_2 = put(new(), :key, "value", @timestamp_1)

      result = delta(crdt_1, crdt_2)

      assert result == [{:put, :key, "value", @timestamp_1}]
    end

    test "returns delete operation for deleted key in target" do
      crdt_1 = new()
      crdt_2 = delete(new(), :key, @timestamp_1)

      result = delta(crdt_1, crdt_2)

      assert result == [{:delete, :key, @timestamp_1}]
    end

    test "returns put operation for newer value in target" do
      crdt_1 = put(new(), :key, "value_1", @timestamp_1)
      crdt_2 = put(new(), :key, "value_2", @timestamp_2)

      result = delta(crdt_1, crdt_2)

      assert result == [{:put, :key, "value_2", @timestamp_2}]
    end

    test "returns no operation for older value in target" do
      crdt_1 = put(new(), :key, "value_1", @timestamp_2)
      crdt_2 = put(new(), :key, "value_2", @timestamp_1)

      result = delta(crdt_1, crdt_2)

      assert result == []
    end

    test "returns multiple operations for complex differences" do
      crdt_1 =
        new()
        |> put(:key_1, "value_1", @timestamp_1)
        |> put(:key_2, "value_2", @timestamp_1)

      crdt_2 =
        new()
        |> put(:key_1, "new_value", @timestamp_2)
        |> delete(:key_2, @timestamp_2)
        |> put(:key_3, "value_3", @timestamp_1)

      result = delta(crdt_1, crdt_2)

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
      crdt = new()

      assert empty?(crdt)
    end

    test "returns false when CRDT has entries" do
      crdt = put(new(), :key, "value", @timestamp_1)

      refute empty?(crdt)
    end

    test "returns true when all entries are deleted" do
      crdt =
        new()
        |> put(:key, "value", @timestamp_1)
        |> delete(:key, @timestamp_2)

      assert empty?(crdt)
    end
  end

  describe "get/2" do
    test "returns nil for non-existent key" do
      crdt = new()

      assert get(crdt, :non_existent) == nil
    end

    test "returns value for existing key" do
      crdt = put(new(), :key, "value", @timestamp_1)

      assert get(crdt, :key) == "value"
    end

    test "returns nil for deleted key" do
      crdt =
        new()
        |> put(:key, "value", @timestamp_1)
        |> delete(:key, @timestamp_2)

      assert get(crdt, :key) == nil
    end
  end

  describe "merge/2" do
    test "merges two empty CRDTs" do
      crdt_1 = new()
      crdt_2 = new()

      result = merge(crdt_1, crdt_2)

      assert empty?(result)
    end

    test "merges CRDT with non-overlapping keys" do
      crdt_1 = put(new(), :key_1, "value_1", @timestamp_1)
      crdt_2 = put(new(), :key_2, "value_2", @timestamp_1)

      result = merge(crdt_1, crdt_2)

      assert size(result) == 2
      assert get(result, :key_1) == "value_1"
      assert get(result, :key_2) == "value_2"
    end

    test "merges CRDTs with newer timestamp winning" do
      crdt_1 = put(new(), :key, "value_1", @timestamp_1)
      crdt_2 = put(new(), :key, "value_2", @timestamp_2)

      result = merge(crdt_1, crdt_2)

      assert get(result, :key) == "value_2"
      assert result.entries[:key].timestamp == @timestamp_2
    end

    test "merges CRDTs with deletion winning over older put" do
      crdt_1 = put(new(), :key, "value", @timestamp_1)
      crdt_2 = delete(new(), :key, @timestamp_2)

      result = merge(crdt_1, crdt_2)

      assert get(result, :key) == nil
      assert result.entries[:key].deleted == true
    end

    test "merges CRDTs with put winning over older deletion" do
      crdt_1 = delete(new(), :key, @timestamp_1)
      crdt_2 = put(new(), :key, "value", @timestamp_2)

      result = merge(crdt_1, crdt_2)

      assert get(result, :key) == "value"
      assert result.entries[:key].deleted == false
    end
  end

  describe "new/0" do
    test "creates an empty CRDT map" do
      assert new() == %Hologram.CRDT.Map{entries: %{}}
    end
  end

  describe "put/4" do
    test "creates correct entry structure for new key" do
      result = put(new(), :key, "value", @timestamp_1)

      assert result.entries[:key] == %{
               value: "value",
               timestamp: @timestamp_1,
               deleted: false
             }
    end

    test "adds a new entry with current timestamp when none provided" do
      result = put(new(), :key, "value")

      assert get(result, :key) == "value"
      assert result.entries[:key].timestamp > 0
    end

    test "adds a new entry with provided timestamp" do
      result = put(new(), :key, "value", @timestamp_1)

      assert get(result, :key) == "value"
      assert result.entries[:key].timestamp == @timestamp_1
    end

    test "creates correct entry structure when updating existing key" do
      result =
        new()
        |> put(:key, "old_value", @timestamp_1)
        |> put(:key, "new_value", @timestamp_2)

      assert result.entries[:key] == %{
               value: "new_value",
               timestamp: @timestamp_2,
               deleted: false
             }
    end

    test "updates an existing entry when newer timestamp" do
      result =
        new()
        |> put(:key, "value_1", @timestamp_1)
        |> put(:key, "value_2", @timestamp_2)

      assert get(result, :key) == "value_2"
      assert result.entries[:key].timestamp == @timestamp_2
    end

    test "ignores update when older timestamp" do
      result =
        new()
        |> put(:key, "value_1", @timestamp_2)
        |> put(:key, "value_2", @timestamp_1)

      assert get(result, :key) == "value_1"
      assert result.entries[:key].timestamp == @timestamp_2
    end

    test "ignores update when same timestamp" do
      result =
        new()
        |> put(:key, "value_1", @timestamp_1)
        |> put(:key, "value_2", @timestamp_1)

      assert get(result, :key) == "value_1"
    end

    test "can resurrect deleted entry with newer timestamp" do
      result =
        new()
        |> put(:key, "value_1", @timestamp_1)
        |> delete(:key, @timestamp_2)
        |> put(:key, "value_2", @timestamp_3)

      assert get(result, :key) == "value_2"
      assert result.entries[:key].timestamp == @timestamp_3
      assert result.entries[:key].deleted == false
    end
  end

  describe "size/1" do
    test "returns 0 for empty CRDT" do
      crdt = new()

      assert size(crdt) == 0
    end

    test "returns correct count for non-deleted entries" do
      crdt =
        new()
        |> put(:key_1, "value_1", @timestamp_1)
        |> put(:key_2, "value_2", @timestamp_1)
        |> put(:key_3, "value_3", @timestamp_1)

      assert size(crdt) == 3
    end

    test "excludes deleted entries from count" do
      crdt =
        new()
        |> put(:key_1, "value_1", @timestamp_1)
        |> put(:key_2, "value_2", @timestamp_1)
        |> delete(:key_2, @timestamp_2)

      assert size(crdt) == 1
    end
  end

  describe "to_map/1" do
    test "returns empty map for empty CRDT" do
      crdt = new()

      assert to_map(crdt) == %{}
    end

    test "returns map with non-deleted entries" do
      crdt =
        new()
        |> put(:key_1, "value_1", @timestamp_1)
        |> put(:key_2, "value_2", @timestamp_1)

      result = to_map(crdt)

      assert result == %{key_1: "value_1", key_2: "value_2"}
    end

    test "excludes deleted entries" do
      crdt =
        new()
        |> put(:key_1, "value_1", @timestamp_1)
        |> put(:key_2, "value_2", @timestamp_1)
        |> delete(:key_2, @timestamp_2)

      result = to_map(crdt)

      assert result == %{key_1: "value_1"}
    end
  end

  describe "CRDT properties" do
    test "idempotency: applying same operation multiple times has same effect" do
      # Test with put operation
      crdt_1 = new()
      crdt_2 = put(crdt_1, :key, "value", @timestamp_1)
      crdt_3 = put(crdt_2, :key, "value", @timestamp_1)
      assert crdt_2 == crdt_3

      # Test with deletion operation
      crdt_4 = delete(crdt_3, :key, @timestamp_2)
      crdt_5 = delete(crdt_4, :key, @timestamp_2)
      assert crdt_4 == crdt_5

      # Test with conflicting operations (older timestamp should be ignored)
      crdt_6 = put(crdt_5, :key, "old_value", @timestamp_1)
      crdt_7 = put(crdt_6, :key, "old_value", @timestamp_1)
      assert crdt_6 == crdt_7
      # Should still be deleted
      assert get(crdt_7, :key) == nil
    end

    test "commutativity: order of merge doesn't matter with conflicts" do
      # Test with overlapping keys and conflicting timestamps

      crdt_1 =
        new()
        |> put(:key_1, "value_1a", @timestamp_1)
        |> put(:key_2, "value_2a", @timestamp_3)
        |> delete(:key_3, @timestamp_2)

      crdt_2 =
        new()
        |> put(:key_1, "value_1b", @timestamp_2)
        |> put(:key_2, "value_2b", @timestamp_1)
        |> put(:key_3, "value_3", @timestamp_4)
        |> put(:key_4, "value_4", @timestamp_1)

      merged_1_2 = merge(crdt_1, crdt_2)
      merged_2_1 = merge(crdt_2, crdt_1)

      # Should have identical internal structure regardless of merge order
      assert merged_1_2 == merged_2_1

      # Verify specific conflict resolutions
      # timestamp_2 > timestamp_1
      assert get(merged_1_2, :key_1) == "value_1b"
      # timestamp_3 > timestamp_1
      assert get(merged_1_2, :key_2) == "value_2a"
      # timestamp_4 > timestamp_2 (delete)
      assert get(merged_1_2, :key_3) == "value_3"
      # only in crdt_2
      assert get(merged_1_2, :key_4) == "value_4"
    end

    test "associativity: grouping of merges doesn't matter with complex conflicts" do
      # Create CRDTs with overlapping keys and various timestamps

      crdt_1 =
        new()
        |> put(:key_1, "value_1a", @timestamp_1)
        |> put(:key_2, "value_2a", @timestamp_3)
        |> delete(:key_4, @timestamp_1)

      crdt_2 =
        new()
        |> put(:key_1, "value_1b", @timestamp_2)
        |> put(:key_3, "value_3a", @timestamp_2)
        |> put(:key_4, "value_4a", @timestamp_3)

      crdt_3 =
        new()
        |> put(:key_2, "value_2b", @timestamp_1)
        |> put(:key_3, "value_3b", @timestamp_4)
        |> delete(:key_4, @timestamp_4)

      # Test (crdt_1 ∪ crdt_2) ∪ crdt_3
      merged_left =
        crdt_1
        |> merge(crdt_2)
        |> merge(crdt_3)

      # Test crdt_1 ∪ (crdt_2 ∪ crdt_3)
      merged_right = merge(crdt_1, merge(crdt_2, crdt_3))

      assert merged_left == merged_right

      # Verify final conflict resolutions
      # timestamp_2 wins
      assert get(merged_left, :key_1) == "value_1b"
      # timestamp_3 wins
      assert get(merged_left, :key_2) == "value_2a"
      # timestamp_4 wins
      assert get(merged_left, :key_3) == "value_3b"
      # deleted at timestamp_4
      assert get(merged_left, :key_4) == nil
    end

    test "convergence: concurrent operations eventually converge" do
      # Simulate concurrent operations on the same keys from different replicas
      base_crdt = put(new(), :shared, "initial", @timestamp_1)

      # Replica A operations
      replica_a =
        base_crdt
        |> put(:shared, "from_a", @timestamp_3)
        |> put(:a_only, "a_value", @timestamp_2)
        |> delete(:to_delete, @timestamp_2)

      # Replica B operations (simulating concurrent updates)
      replica_b =
        base_crdt
        # Older timestamp
        |> put(:shared, "from_b", @timestamp_2)
        |> put(:b_only, "b_value", @timestamp_3)
        |> put(:to_delete, "will_be_deleted", @timestamp_1)

      # Both replicas should converge to the same state regardless of merge order
      converged_ab = merge(replica_a, replica_b)
      converged_ba = merge(replica_b, replica_a)

      assert converged_ab == converged_ba

      # Verify LWW semantics
      # timestamp_3 > timestamp_2
      assert get(converged_ab, :shared) == "from_a"
      assert get(converged_ab, :a_only) == "a_value"
      assert get(converged_ab, :b_only) == "b_value"
      # Delete wins over put
      assert get(converged_ab, :to_delete) == nil
    end

    test "monotonicity: merge never loses information from newer timestamps" do
      crdt_old =
        new()
        |> put(:key_1, "old", @timestamp_1)
        |> put(:key_2, "keep", @timestamp_3)

      crdt_new =
        new()
        |> put(:key_1, "new", @timestamp_2)
        # Older than existing put
        |> delete(:key_2, @timestamp_1)
        |> put(:key_3, "added", @timestamp_2)

      merged = merge(crdt_old, crdt_new)

      # Should preserve the newest information for each key
      # timestamp_2 > timestamp_1
      assert get(merged, :key_1) == "new"
      # timestamp_3 > timestamp_1 (delete ignored)
      assert get(merged, :key_2) == "keep"
      # new key added
      assert get(merged, :key_3) == "added"
    end

    test "delta and apply_delta round trip with complex operations" do
      # Start with a CRDT that has some data and deletions
      crdt_1 =
        new()
        |> put(:key_1, "old_value_1", @timestamp_1)
        |> put(:key_2, "value_2", @timestamp_1)
        |> delete(:key_3, @timestamp_1)

      # Create target CRDT with various operations including resurrections
      crdt_2 =
        new()
        # Update existing
        |> put(:key_1, "new_value_1", @timestamp_3)
        # Delete existing
        |> delete(:key_2, @timestamp_2)
        # Resurrect deleted
        |> put(:key_3, "resurrected", @timestamp_2)
        # New key
        |> put(:key_4, "new_value_4", @timestamp_1)

      delta_ops = delta(crdt_1, crdt_2)
      result = apply_delta(crdt_1, delta_ops)

      assert result == crdt_2

      # Verify specific outcomes
      assert get(result, :key_1) == "new_value_1"
      assert get(result, :key_2) == nil
      assert get(result, :key_3) == "resurrected"
      assert get(result, :key_4) == "new_value_4"
    end
  end
end
