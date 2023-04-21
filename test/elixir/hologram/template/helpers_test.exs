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

    test "void SVG element" do
      assert void_element?("path")
    end

    test "slot element" do
      assert void_element?("slot")
    end

    test "non-void HTML element" do
      refute void_element?("div")
    end

    test "non-void SVG element" do
      refute void_element?("g")
    end
  end
end
