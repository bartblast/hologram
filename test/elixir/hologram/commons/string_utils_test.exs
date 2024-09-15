defmodule Hologram.Commons.StringUtilsTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Commons.StringUtils

  test "prepend/2" do
    assert prepend("abc", "xyz") == "xyzabc"
  end

  describe "prepend_if_not_empty/2" do
    test "not empty" do
      assert prepend_if_not_empty("abc", "xyz") == "xyzabc"
    end

    test "empty" do
      assert prepend_if_not_empty("", "xyz") == ""
    end
  end

  describe "starts_with_lowercase?/1" do
    test "returns true for a string starting with lowercase letter" do
      assert starts_with_lowercase?("hello")
    end

    test "returns false for a string starting with uppercase letter" do
      refute starts_with_lowercase?("World")
    end

    test "returns false for an empty string" do
      refute starts_with_lowercase?("")
    end

    test "returns true for a string starting with a non-alphabetic character" do
      assert starts_with_lowercase?("123abc")
    end

    test "returns true for a string containing only non-alphabetic characters" do
      assert starts_with_lowercase?("!@#$")
    end
  end

  test "wrap/3" do
    assert wrap("ab", "cd", "ef") == "cdabef"
  end
end
