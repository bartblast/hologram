defmodule Hologram.Compiler.HelpersTest do
  use Hologram.Test.UnitCase, async: true
  alias Hologram.Compiler.Helpers

  describe "alias_segments/1" do
    test "alias" do
      assert Helpers.alias_segments(Aaa.Bbb) == [:Aaa, :Bbb]
    end

    test "string" do
      assert Helpers.alias_segments("Aaa.Bbb") == [:Aaa, :Bbb]
    end
  end
end
