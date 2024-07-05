defmodule Hologram.Commons.AtomUtilsTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Commons.AtomUtils

  describe "starts_with?/2" do
    test "starts with" do
      assert starts_with?(:abcde, "abc") == true
    end

    test "doesn't start with" do
      assert starts_with?(:abcde, "bcd") == false
    end
  end
end
