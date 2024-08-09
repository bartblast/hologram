defmodule Hologram.Commons.GuardsTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Commons.Guards

  describe "is_regex/1" do
    test "regex" do
      assert is_regex(~r/abc/)
    end

    test "not regex" do
      refute is_regex(wrap_term(123))
    end
  end
end
