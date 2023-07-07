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

  describe "module/1" do
    test "single item list when the item is a module" do
      assert module([String]) == String
    end

    test "single item list when the item is not a module" do
      assert module([:String]) == String
    end

    test "multiple alias segments, when first alias segment is not 'Elixir'" do
      assert module([:Hologram, :Compiler, :HelpersTest]) == Hologram.Compiler.HelpersTest
    end

    test "multiple alias segments, when first alias segment is 'Elixir'" do
      assert module([:"Elixir", :Hologram, :Compiler, :HelpersTest]) ==
               Hologram.Compiler.HelpersTest
    end
  end
end
