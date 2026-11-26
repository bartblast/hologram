defmodule Hologram.DB.WordSQLTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.DB.WordSQL

  describe "at_split/3" do
    test "skips the empty part the separator put before the text gives" do
      assert at_split("t", "$1", 0) == "(string_to_array($1 || (t), $1))[2]"
      assert at_split("t", "$1", 2) == "(string_to_array($1 || (t), $1))[4]"
    end
  end

  describe "coalesce/1" do
    test "takes the values in order" do
      assert coalesce(["a", "b", "c"]) == "COALESCE(a, b, c)"
    end
  end

  describe "concat/1" do
    test "joins the operands" do
      assert concat(["a", "b", "c"]) == "(a || b || c)"
    end
  end

  describe "count/1" do
    test "counts the source's rows" do
      assert count("FROM t WHERE x") == "(SELECT COUNT(*) FROM t WHERE x)"
    end
  end

  describe "most_common/3" do
    test "groups by the value and breaks a tie by its sort key, then itself" do
      assert most_common("v", "k", "FROM t WHERE x") ==
               "(SELECT v FROM t WHERE x AND v IS NOT NULL " <>
                 "GROUP BY v ORDER BY COUNT(*) DESC, MIN(k), v LIMIT 1)"
    end

    test "breaks a tie by the value alone with no sort key" do
      assert most_common("v", nil, "FROM t WHERE x") ==
               "(SELECT v FROM t WHERE x AND v IS NOT NULL " <>
                 "GROUP BY v ORDER BY COUNT(*) DESC, v LIMIT 1)"
    end
  end
end
