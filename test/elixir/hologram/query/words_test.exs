defmodule Hologram.Query.WordsTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Query.Words

  describe "at/2" do
    test "counts from 0" do
      assert at(["a", "b"], 0) == "a"
      assert at(["a", "b"], 1) == "b"
    end

    test "gives nil past the end" do
      assert at(["a"], 1) == nil
    end

    test "gives nil for a nil list" do
      assert at(nil, 0) == nil
    end
  end

  describe "coalesce/1" do
    test "gives the first value that isn't nil" do
      assert coalesce([nil, "a", "b"]) == "a"
    end

    test "gives nil when all are nil" do
      assert coalesce([nil, nil]) == nil
    end

    test "takes false as a value" do
      assert coalesce([nil, false, true]) == false
    end

    test "takes an empty string as a value" do
      assert coalesce(["", "a"]) == ""
    end
  end

  describe "concat/1" do
    test "joins strings" do
      assert concat(["a", " ", "b"]) == "a b"
    end

    test "gives nil when any operand is nil" do
      assert concat(["a", nil, "b"]) == nil
    end

    test "keeps empty strings" do
      assert concat(["", "a"]) == "a"
    end
  end

  describe "count/1" do
    test "counts rows" do
      assert count([%{}, %{}]) == 2
    end

    test "gives 0 for no rows" do
      assert count([]) == 0
    end
  end

  describe "most_common/2" do
    test "gives the most frequent value" do
      assert most_common(["a", "b", "b"]) == "b"
    end

    test "skips nil" do
      assert most_common([nil, nil, "a"]) == "a"
    end

    test "gives nil over no values" do
      assert most_common([]) == nil
    end

    test "gives nil when every value is nil" do
      assert most_common([nil, nil]) == nil
    end

    test "gives a tie to the smallest in sort order, not byte order" do
      assert most_common(["Zebra", "apple"]) == "apple"
    end

    test "keeps strings differing only in case apart" do
      assert most_common(["apple", "Apple", "Apple"]) == "Apple"
    end

    test "settles a tie on equal sort keys by the value" do
      assert most_common(["apple", "Apple"]) == "Apple"
    end

    test "orders an enum tie by its declared position" do
      assert most_common([:b, :a], %{b: 0, a: 1}) == :b
    end

    test "groups integers" do
      assert most_common([3, 1, 3, 2]) == 3
    end

    test "gives an integer tie to the smallest" do
      assert most_common([2, 1]) == 1
    end

    test "groups booleans" do
      assert most_common([true, false, true]) == true
    end

    test "gives a boolean tie to false" do
      assert most_common([true, false]) == false
    end

    test "orders dates chronologically across a year boundary" do
      assert most_common([~D[2026-01-01], ~D[2025-12-31]]) == ~D[2025-12-31]
    end

    test "groups datetimes equal at different precisions" do
      assert most_common([
               ~U[2026-01-01 00:00:00Z],
               ~U[2026-01-01 00:00:00.000Z],
               ~U[2025-01-01 00:00:00Z]
             ]) == ~U[2026-01-01 00:00:00Z]
    end

    test "groups times" do
      assert most_common([~T[10:00:00], ~T[09:00:00], ~T[10:00:00]]) == ~T[10:00:00]
    end
  end

  describe "split/2" do
    test "splits as String.split/2" do
      assert split("a, b", ", ") == ["a", "b"]
    end

    test "keeps empty parts at either end" do
      assert split(",a,", ",") == ["", "a", ""]
    end

    test "gives the whole text when the separator is absent" do
      assert split("a", ",") == ["a"]
    end

    test "gives one empty part for an empty string" do
      assert split("", ",") == [""]
    end

    test "gives nil for nil" do
      assert split(nil, ",") == nil
    end
  end
end
