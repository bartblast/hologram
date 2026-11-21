defmodule Hologram.DB.WordSQLTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.DB.WordSQL

  describe "at_split/3" do
    test "reads the position from 1 and answers an empty text as one empty part" do
      assert at_split("t", "$1", 0) ==
               "(CASE WHEN t = '' THEN ''::text ELSE (string_to_array(t, $1))[1] END)"
    end

    test "gives NULL past the one part of an empty text" do
      assert at_split("t", "$1", 2) ==
               "(CASE WHEN t = '' THEN NULL::text ELSE (string_to_array(t, $1))[3] END)"
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
end
