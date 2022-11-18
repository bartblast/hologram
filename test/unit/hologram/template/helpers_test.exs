defmodule Hologram.Template.HelpersTest do
  use Hologram.Test.UnitCase, async: true
  alias Hologram.Template.Helpers

  describe "tag_type/1" do
    test "element" do
      assert Helpers.tag_type("div") == :element
    end

    test "component" do
      assert Helpers.tag_type("MyComponent") == :component
    end
  end

  describe "void_element?/1" do
    test "void HTML element" do
      assert Helpers.void_element?("br")
    end

    test "void SVG element" do
      assert Helpers.void_element?("path")
    end

    test "slot element" do
      assert Helpers.void_element?("slot")
    end

    test "non-void HTML element" do
      refute Helpers.void_element?("div")
    end

    test "non-void SVG element" do
      refute Helpers.void_element?("g")
    end
  end
end
