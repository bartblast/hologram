defmodule Hologram.Compiler.HelpersTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.Helpers

  describe "alias_segments/1" do
    test "alias" do
      assert alias_segments(Aaa.Bbb) == [:Aaa, :Bbb]
    end

    test "string" do
      assert alias_segments("Aaa.Bbb") == [:Aaa, :Bbb]
    end
  end

  test "module/1" do
    assert module([:Hologram, :Compiler, :HelpersTest]) == Hologram.Compiler.HelpersTest
  end
end
