defmodule Hologram.Template.HelpersTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Template.Helpers

  describe "tag_type/1" do
    test "element" do
      assert tag_type("div") == :element
    end

    test "component" do
      assert tag_type("MyComponent") == :component
    end
  end

  describe "void_element?/1" do
    test "void HTML element" do
      assert void_element?("br")
    end

    test "non-void HTML element" do
      refute void_element?("div")
    end

    test "slot element" do
      assert void_element?("slot")
    end

    test "SVG element that can be self-closed" do
      refute void_element?("path")
    end
  end
end
